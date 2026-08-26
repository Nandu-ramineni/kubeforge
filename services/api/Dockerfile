# syntax=docker/dockerfile:1

# ---- deps stage --------------------------------------------------------
# Isolated so the (potentially large, cacheable) npm install layer never has
# to re-run just because application source changed. Only package.json /
# package-lock.json invalidate this layer.
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# npm ci (not npm install): fails if package.json and package-lock.json are
# out of sync, and installs exactly what's in the lockfile - reproducible
# builds instead of "works on my machine". --omit=dev keeps devDependencies
# (test runners, linters added in later phases) out of the runtime image.
RUN npm ci --omit=dev

# AWS RDS enforces SSL, and Node's default trusted-root store does NOT
# reliably cover RDS's certificate chain (confirmed the hard way: a real
# connection attempt against real RDS failed with SELF_SIGNED_CERT_IN_CHAIN
# using rejectUnauthorized:true alone, with no ca specified). AWS's official,
# stable global CA bundle is fetched here at build time; the grep check
# fails the build loudly if the download ever returns something that isn't
# actually a certificate (a CDN error page, a redirect to a login wall,
# etc) instead of silently baking in garbage that would only surface as a
# confusing runtime failure later. curl itself never makes it into the final
# image - only the ~1KB .pem file does, via the COPY --from=deps below.
RUN apk add --no-cache curl && \
    curl -sSf https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /rds-ca-bundle.pem && \
    grep -q "BEGIN CERTIFICATE" /rds-ca-bundle.pem

# ---- runtime stage ------------------------------------------------------
# Fresh alpine base, not "FROM deps" - anything only needed to install
# packages (npm cache, package-lock.json itself) is left behind, not carried
# into the image that actually ships.
FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# See services/worker/Dockerfile for the full explanation.
RUN apk update && apk upgrade --no-cache

# node:*-alpine ships a non-root "node" user (uid 1000) out of the box -
# reuse it rather than defining a new one. Running as root inside a
# container that only ever runs one process buys nothing and turns any
# future RCE into a much worse day.
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --from=deps --chown=node:node /rds-ca-bundle.pem ./rds-ca-bundle.pem
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

# npm is never used at runtime - only `node src/index.js` runs in this
# stage. Removing it strips npm's own internally-bundled dependencies from
# the shipped image too, which is what a real Trivy finding (CVE-2026-12151,
# undici) turned out to actually be: `npm ls undici` against this project's
# own package-lock.json comes back completely empty, so the vulnerable copy
# Trivy found wasn't anything this project depends on at all - it was npm's
# own internal tooling dependency, bundled into every node:*-alpine image
# regardless of what the project itself needs. Smaller image, smaller
# attack surface, and one less thing whose vulnerabilities aren't ours to
# track via npm audit in the first place.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

USER node

EXPOSE 3000

# No curl/wget installed on purpose (smaller attack surface, smaller image) -
# Node itself can make the request. This HEALTHCHECK matters for plain
# `docker run` / docker-compose; Kubernetes ignores it in favor of its own
# liveness/readiness probes wired up in Phase 9, but it's cheap to have and
# useful outside a cluster too.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/health/live',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/index.js"]
