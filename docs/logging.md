# Phase 12 — Loki Logging

## A real gap this phase found and fixed, unrelated to logging itself

While checking whether Alloy's log collection could be blocked by Phase 9's
NetworkPolicy, a bigger question came up: **has NetworkPolicy enforcement
ever actually been active on this cluster at all?**

Confirmed via AWS's own announcement: EKS's VPC CNI has supported
NetworkPolicy enforcement since v1.14, but it ships **off by default** even
on a brand new cluster. Our Terraform never explicitly turned it on. That
means every NetworkPolicy object applied since Phase 9 has been valid,
accepted by the API server, and completely inert - the "default deny"
never actually denied anything. This also explains something that should
have been a clue earlier: Prometheus has been scraping `worker`'s
`/metrics` successfully (Phase 11) despite `worker` never having an
explicit NetworkPolicy ingress rule at all.

Fixed in two parts, together, in this phase:

1. `infrastructure/terraform/modules/eks`'s new `aws_eks_addon.vpc_cni`
   resource explicitly enables `enableNetworkPolicy`. Uses
   `resolve_conflicts_on_create = "OVERWRITE"` to adopt the add-on EKS
   already auto-created, rather than erroring the way the GitHub OIDC
   provider did back in Phase 5 (that resource has no adoption mechanism;
   this one is specifically designed for it).
2. `helm/kubeforge/templates/networkpolicy.yaml` now gives any service with
   `metrics.enabled: true` an explicit ingress rule from the `monitoring`
   namespace, independent of `publicIngress`. Without this, turning
   enforcement on would have immediately broken Prometheus's access to
   `worker` the moment it went from inert to real.

**Apply the Terraform before syncing this phase's Helm changes** - if
enforcement turns on before the corrected NetworkPolicy is live, Prometheus
briefly loses `worker` in between.

## Why Alloy, not Promtail

Promtail reached end-of-life March 2, 2026 - no further security or bug
fixes, ever. All new development is in Grafana Alloy. Using Promtail in a
project built after that date would mean deliberately choosing dead
software.

## Why grafana-community/helm-charts, not grafana/helm-charts, for Loki specifically

As of March 16, 2026 the Loki chart forked to a community-maintained repo
for open-source users; the original repo now only maintains it for paying
Grafana Enterprise Logs customers. Checked this directly rather than trust
older tutorials, most of which still reference the pre-fork repo. Alloy's
chart did **not** move - it stays under the original `grafana/helm-charts`
repo. Easy to get wrong by assuming both charts moved together; they
didn't.

## Why SingleBinary mode and filesystem storage, not SimpleScalable/S3

SimpleScalable mode is itself being deprecated, and its default topology is
9+ pods (3 read, 3 write, 3 backend) before storing a single log line -
built for a scale this project doesn't have. SingleBinary runs every Loki
component in one process; the official docs recommend it for "a few tens of
GB/day," comfortably covering this project's real log volume.

S3-backed storage was considered and set aside for now: the chart's bundled
MinIO subchart is being removed entirely on 2026-10-31, and correctly
configuring real external S3 storage for this specific, fast-moving chart
version involves enough schema detail (`schemaConfig`, `storage_config`,
named stores) that getting it wrong silently was a real risk without a live
cluster to verify against. Filesystem storage (PVC-backed) has no
deprecation timeline and is entirely sufficient to prove out real
collection and search now - migrating to S3 later is a contained,
legitimate follow-up, not a requirement this phase skipped.

## One-time setup

**1. Apply the Terraform first** (enables NetworkPolicy enforcement):
```bash
cd infrastructure/terraform/environments/dev
terraform apply
```

**2. Push the Helm chart changes** (corrected NetworkPolicy + new Loki
datasource ConfigMap) and wait for Argo CD to sync before continuing:
```bash
git add . && git commit -m "Phase 12: Loki logging + NetworkPolicy enforcement fix" && git push
kubectl get application kubeforge-dev -n argocd -w
```

**3. Install Loki:**
```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm install loki grafana-community/loki -n monitoring -f monitoring/loki/values.yaml
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
```

**4. Confirm the Loki Service name matches what Alloy and the Grafana
datasource assume:**
```bash
kubectl get svc -n monitoring | grep loki
```
Both `monitoring/alloy/config.alloy` and
`helm/kubeforge/templates/grafana-datasource.yaml` assume
`loki.monitoring.svc.cluster.local:3100`. If your actual Service name
differs, update both before continuing.

**5. Install Alloy:**
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install alloy grafana/alloy -n monitoring \
  --set-file alloy.configMap.content=monitoring/alloy/config.alloy
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy
```

**6. Enable Grafana's datasource sidecar** (separate flag from Phase 11's
dashboard sidecar - upgrading the existing release, not a fresh install):
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values \
  --set grafana.sidecar.datasources.enabled=true \
  --set grafana.sidecar.datasources.searchNamespace=ALL
```

## Verify logs are actually flowing

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=50
```
Look for lines indicating successful writes to Loki, not connection errors.

In Grafana (`kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`),
open **Explore**, select the **Loki** datasource, and run:
```logql
{namespace="kubeforge"}
```
You should see real, live log lines from every KubeForge pod.

## Real LogQL queries for incident investigation - the actual point of this phase

Our structured JSON logging (pino, since Phase 2) is what makes these
possible - Loki's `| json` operator parses each log line's fields on the
fly at query time.

**Every error, across every service, right now:**
```logql
{namespace="kubeforge"} | json | level="error"
```

**Every log line for one specific request, tracing it across services:**
```logql
{namespace="kubeforge"} | json | requestId="<a real requestId from a log line or response header>"
```
This is the actual "investigate an incident" workflow: grab the
`x-request-id` header from a failed response, paste it into this query, and
see every log line that request touched - api's handling, any retry
warnings, the eventual error - in one place, instead of running
`kubectl logs` against each pod by hand.

**Only api's logs, filtered further:**
```logql
{namespace="kubeforge", app="api"} | json | status_code>=500
```

**Rate of error-level logs over time** (useful as an actual alert
condition, revisited properly in Phase 14):
```logql
sum(rate({namespace="kubeforge"} | json | level="error" [5m]))
```

## Honest gap: no `traceId` yet

Section 16 of `docs/architecture.md` describes a log shape including
`traceId`. Every log line already carries `timestamp`, `level`, `service`,
and `message` (pino's base config since Phase 2), and most carry
`requestId` (via `pino-http` and explicit logging calls) - but `traceId`
doesn't exist anywhere in this codebase yet. That's not an oversight here;
it's OpenTelemetry's job, and OpenTelemetry is Phase 13, immediately next.
Once distributed tracing exists, this is the natural place to come back and
wire trace IDs into every log line too.

## Verified, given the same limitation as every earlier phase

`helm` isn't reachable from this sandbox, and Alloy's River configuration
language isn't something the chart-rendering approach used for our own
Helm chart can verify at all - it's a genuinely different config language,
not Go templates. What was checked: both new Terraform resources validate
syntactically and were cross-checked against the full 41-file tree; the
corrected `networkpolicy.yaml` was rendered and confirmed to give `worker`
exactly the one ingress rule it needs, no more; the Loki and datasource
YAML files were validated as parseable. What couldn't be checked from here:
whether Alloy's River config is free of syntax errors, and whether the
assumed Loki Service name is correct for your actual install - both are
called out explicitly above as the first things to verify once this is
running for real.
