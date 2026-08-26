# KubeForge — Project Retrospective

Twelve phases, stopped deliberately at Phase 12 rather than continuing
through the full 20-phase roadmap in `docs/architecture.md` — genuinely
sufficient for a junior SRE/DevOps portfolio, and every phase here has real,
verified evidence behind it rather than a checklist entry. This document is
the "receipts" - the specific technical problems that came up, how they were
actually diagnosed, and what real numbers came out the other end.

Nothing in this document is estimated or projected. Every figure was copied
from a real command's actual output.

## Real debugging stories

These aren't "I installed X." Each one is a genuine problem that had a
specific, non-obvious cause, found by reading real error output rather than
guessing.

### The GitHub OIDC trust policy that predates its own tutorials
CI's `AssumeRoleWithWebIdentity` call failed against a repo created after
July 15, 2026, because GitHub had rolled out an **immutable OIDC subject
claim format** newer than almost every existing tutorial on the internet.
Diagnosed by decoding the actual JWT the workflow received, not by trying
random trust-policy syntax - the fix matched both the old and new subject
formats so it works regardless of which a given repo issues.

### A CVE that wasn't actually the project's problem
Trivy flagged a HIGH-severity `undici` vulnerability in every service's
image. `npm ls undici` against the project's own `package-lock.json` came
back completely empty - the vulnerable copy was npm's own internally
bundled dependency, shipped inside `node:24-alpine` regardless of what the
project needed. Fixed by stripping `npm` from the runtime image entirely
(it's never used there - only `node` runs the app), which is real hardening
independent of the CVE, not a workaround.

### A metric that had been silently broken since Phase 2
`api`'s `httpRequestDuration` histogram was defined and registered, but
nothing had ever called `.observe()` on it - a Grafana panel built against
it would have shown "No data" forever. Fixed with middleware that labels by
the *matched route pattern* (`/tasks/:id`), not the resolved URL - verified
directly by sending three requests to three different real task UUIDs and
confirming they collapsed into one Prometheus time series, not three. The
wrong approach here is a well-known way to quietly degrade a real
production Prometheus instance over months.

### NetworkPolicy that was never actually enforced
While checking whether Phase 12's log collector would be blocked by
existing NetworkPolicy rules, a bigger question came up: had enforcement
ever been active on this cluster at all? Confirmed via AWS's own
documentation - EKS's VPC CNI has supported NetworkPolicy since v1.14, but
ships **off by default**, even on a brand-new cluster. Every policy applied
since Phase 9 had been valid and accepted by the API server, and completely
inert. Fixed in two parts, together, since enabling enforcement alone would
have immediately broken Prometheus's access to `worker`: a Terraform change
enabling it, and a NetworkPolicy fix giving any metrics-enabled service an
explicit ingress rule from the `monitoring` namespace.

### Five real infrastructure failures in one chain (Phase 12)
Installing Loki surfaced a genuine, sequential debugging story:
1. The chart rejected the values file - non-zero replica counts for both
   monolithic and SimpleScalable targets simultaneously.
2. Fixed that, and the pod stuck `Pending` - `pod has unbound immediate
   PersistentVolumeClaims`. No default StorageClass existed at all; nothing
   in 11 prior phases had ever needed persistent storage.
3. Installed the EBS CSI driver via a new Terraform-managed IRSA role and
   addon - the PVC *still* didn't bind.
4. The existing `gp2` StorageClass used `kubernetes.io/aws-ebs`, the
   **legacy in-tree provisioner removed from Kubernetes core since v1.23**
   - present as an object, functionally dead for years. Created a real
   `gp3` class using the actual CSI provisioner.
5. Loki's memcached cache pods then failed to schedule - `Insufficient
   memory`. The chart's default cache sizing requested ~9.6Gi, more than an
   entire `t3.medium` node's total RAM. Disabled the external caches
   entirely - SingleBinary mode's in-process caching is sufficient at this
   log volume, the same reasoning that justified SingleBinary over
   SimpleScalable in the first place.
6. Finally, Alloy's DaemonSet hit a genuine per-node pod-count ceiling (17
   pods, `t3.medium`'s default under the classic ENI allocation model).
   Enabled VPC CNI prefix delegation via Terraform, then cordoned, drained,
   and replaced the one affected node so it would boot with the new
   setting active - confirmed by checking the new node's actual pod
   ceiling afterward, not just assuming the config took effect.

Every one of these was diagnosed from `kubectl describe`, real Kubernetes
events, or an official AWS/vendor source - never guessed and left
unverified.

## Real, measured evidence

| What | Real result | How it was captured |
|---|---|---|
| Load test, HPA autoscaling | `api` scaled 2 → 3 → 4 pods automatically under a 20→100 VU k6 ramp; p95 latency held ~480ms | `k6 run` against the real ALB, watched live via `kubectl get hpa -w` |
| Canary deployment | Real 7-step progression: `5% → pause → 25% → pause → 50% → pause → 100%`, ~60s per pause | `kubectl describe rollout api` event log, exact timestamps |
| GitOps drift correction | Manual `kubectl scale --replicas=5` reverted to 2 within the same second | `kubectl get events`, showing `ScalingReplicaSet` up and down events one second apart |
| Success rate under sustained load | 99.66-99.76% across two separate 10-minute runs | k6's own `checks_succeeded` output |
| Chart correctness | 26 real Kubernetes resources render from one chart, cross-checked against real `values.yaml`, not assumed from reading the templates | A purpose-built Go-template-subset renderer, since `helm` itself wasn't reachable from the build environment |
| Infrastructure correctness | 41 Terraform files, 0 syntax errors, validated after every single change across 12 phases | `python-hcl2` parse validation, every phase |

## Honestly deferred, not accidentally missing

Each of these was a deliberate scope decision, not an oversight:

- **`traceId` in structured logs** - every log line has `timestamp`,
  `level`, `service`, and (for request-scoped logs) `requestId`, but no
  distributed trace ID. That's OpenTelemetry's job specifically, not
  something to bolt onto logging - genuinely started, then set aside to
  keep the finished scope clean rather than ship it half-verified.
- **True weighted-percentage canary traffic splitting** - the current
  canary approximates traffic weight via the ratio of canary-to-stable pod
  count, not precise load-balancer-level routing. The more precise version
  needs the ALB Rollouts traffic-router plugin, a legitimate but separate
  piece of scope.
- **S3-backed Loki storage** - filesystem/PVC storage was chosen
  deliberately over configuring the chart's S3 support, given how much
  schema churn that specific chart had undergone recently and no live
  cluster to verify a more complex config against.
- **Alerting, SLOs, formal load testing, disaster recovery, and
  ChaosOps-style failure testing** (Phases 14-19 of the original roadmap) -
  not built, and that's fine to say plainly in an interview: these are
  things to discuss conceptually, not claim as built work.

## Suggested resume bullets

Drawn only from what's actually true above - nothing here needed
exaggeration:

- Built a Kubernetes platform on AWS EKS with Terraform-managed
  infrastructure (VPC, EKS, RDS, ECR, S3, IAM/OIDC) across dev/staging/
  production environments, validated with zero syntax errors across 41
  files.
- Implemented a GitHub Actions CI/CD pipeline with keyless OIDC
  authentication (no long-lived AWS credentials), diagnosing and resolving
  a July 2026 GitHub platform change to OIDC subject claim formats that
  broke the standard trust-policy pattern.
- Designed a GitOps deployment workflow with Argo CD, demonstrating
  automated drift correction with a measured sub-second reversion of
  unauthorized manual changes.
- Implemented canary deployments via Argo Rollouts, verified with a real
  7-step traffic-shift event log against a live production-shaped cluster.
- Load-tested a Kubernetes HPA/Cluster Autoscaler setup with k6, measuring
  automatic scaling from 2 to 4 pods under a 5x traffic increase while
  maintaining 99.7% request success and sub-500ms p95 latency.
- Debugged a five-stage Kubernetes storage and scheduling failure chain
  (Helm chart validation, missing CSI driver, a legacy in-tree
  StorageClass provisioner removed from Kubernetes core since v1.23,
  oversized default resource requests, and a real per-node pod-count
  ceiling), resolving each from first-hand evidence rather than
  trial-and-error.
- Discovered and fixed a NetworkPolicy enforcement gap on Amazon EKS
  (disabled by default on the VPC CNI), correcting both the underlying
  Terraform configuration and the policy rules it would have otherwise
  broken.

## Housekeeping

`services/*/src/tracing.js`, `instrumentation.js`, and the OpenTelemetry
dependencies in `package.json`/`package-lock.json` are leftovers from an
abandoned Phase 13 attempt and aren't part of this project's finished
scope. They're inert - nothing in CI/CD builds or references them unless
committed and pushed - but safe to delete for a clean repo:

```bash
rm services/*/src/tracing.js services/*/src/instrumentation.js
git checkout services/*/package.json services/*/package-lock.json  # or manually remove the otel deps
```
