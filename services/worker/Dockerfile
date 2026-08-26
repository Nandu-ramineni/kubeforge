# syntax=docker/dockerfile:1

# ---- deps stage --------------------------------------------------------
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Same reasoning as services/api/Dockerfile - see that file's comment.
RUN apk add --no-cache curl && \
    curl -sSf https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /rds-ca-bundle.pem && \
    grep -q "BEGIN CERTIFICATE" /rds-ca-bundle.pem

# ---- runtime stage ------------------------------------------------------
FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Patches OS-level packages (openssl/libssl/libcrypto etc) to whatever's
# currently available in Alpine's repos - not our code, not our
# dependencies, but a real HIGH-severity CVE (CVE-2026-14456, libssl3/
# libcrypto3) surfaced by Trivy on a rebuild months after this Dockerfile
# was first written, from a patch Alpine shipped after the base image tag
# was last built. Nothing in this Dockerfile changed; the base image's
# world did - this keeps that from silently going stale again.
RUN apk update && apk upgrade --no-cache

COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --from=deps --chown=node:node /rds-ca-bundle.pem ./rds-ca-bundle.pem
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

# See services/api/Dockerfile for the full explanation of why this is here.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

USER node

# The worker has no application API - this is only the health/metrics port.
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3001/health/live',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "src/index.js"]
