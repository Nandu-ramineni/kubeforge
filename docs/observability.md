# Phase 11 — Prometheus & Grafana

## A real gap this phase closed, not just new features

`api`'s `httpRequestDuration` histogram was **defined back in Phase 2 and
never once recorded** - `services/api/src/metrics.js` registered it, but
nothing ever called `.observe()`. A Grafana panel built against it would
have shown "No data," silently. `services/api/src/middleware/metricsMiddleware.js`
closes this now.

The one detail that actually matters in that fix: it labels by
**`req.route.path`** (the matched pattern, e.g. `/tasks/:id`), not the
resolved URL (`/tasks/8c5cb594-...`). Tested directly - three requests to
three different real task UUIDs correctly collapsed into **one** Prometheus
time series, not three. Labeling by the raw path instead would create a new
time series per unique ID forever, a well-known way to quietly degrade or
crash Prometheus over time (unbounded cardinality).

`worker`'s metrics were already correctly wired since Phase 2 (`startTimer`/
`endTimer` around every processed task) - only `api` had the gap.

## Why PodMonitor, not ServiceMonitor

`worker` deliberately has no Kubernetes Service (nothing routes to it - see
Phase 4's original reasoning). Prometheus Operator's `ServiceMonitor` CRD
discovers targets via a Service's Endpoints, so it can't see `worker` at
all. `PodMonitor` selects pods directly by label, no Service required -
works identically for `api` (which has a Service, for real traffic) and
`worker` (which doesn't). `frontend` gets neither - it has no `/metrics`
endpoint to scrape.

## Why only one custom dashboard, not three

Section 15 of `docs/architecture.md` asks for a Kubernetes Overview
dashboard, an API dashboard, and an Infrastructure dashboard. Only the API
one is custom-built here (`helm/kubeforge/dashboards/api-dashboard.json`) -
`kube-prometheus-stack` already ships well-established, maintained
dashboards for cluster/node/pod resource usage (the kubernetes-mixin
dashboards) out of the box. Hand-building a worse version of something
already solved isn't worth the effort; the API dashboard is the one thing
genuinely specific to this project, querying `http_request_duration_seconds`,
`kubeforge_tasks_created_total`, `kubeforge_tasks_processed_total`, and
`kubeforge_tasks_failed_total` - metrics nothing off-the-shelf would know
to chart.

## One-time setup

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.searchNamespace=ALL
```

`searchNamespace=ALL` matters specifically here - the dashboard ConfigMap
this chart creates lives in the `kubeforge` namespace, not `monitoring`, and
the sidecar only watches namespaces it's told to by default.

Wait for everything up:
```bash
kubectl get pods -n monitoring
```

## Deploy

Push as usual - Argo CD picks up the new PodMonitor/ConfigMap resources on
the next sync:
```bash
git add . && git commit -m "Phase 11: Prometheus + Grafana" && git push
```

## Verify Prometheus is actually scraping real targets

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```
Open `http://localhost:9090/targets` - look for `api` and `worker` under
the PodMonitor-generated jobs, both `State: UP`. If they're not there,
`kubectl get podmonitor -n kubeforge` and `kubectl describe podmonitor api -n kubeforge`
are the first things to check.

## View the dashboard

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```
Open `http://localhost:3000`, log in as `admin`, find **KubeForge - API**
in the dashboard list (auto-loaded via the sidecar, no manual import).

For real data to look at immediately rather than flat lines, rerun Phase
10's load test:
```bash
k6 run -e BASE_URL=http://<your-alb-hostname> scripts/load-tests/api-load-test.js
```
Watch the dashboard update live - request rate, latency percentiles, and
the HPA replica count panel should all move together, the same story
Phase 10 pieced together by hand from `kubectl describe`, now visible on
one screen in real time.

## Verified, given the same limitation as every earlier phase

`helm` isn't reachable from the sandbox this was built in. What was
actually checked: the metrics middleware was run against a real Express app
with real HTTP requests (not mocked), specifically proving the cardinality
fix works; every template (12, producing 25 total Kubernetes resources) was
rendered against the real `values.yaml` and validated as parseable YAML;
the dashboard JSON was validated standalone, then re-extracted from its
rendered ConfigMap and re-parsed to confirm the YAML-embedding process
didn't corrupt it. What couldn't be checked from here: whether the PromQL
queries return sensible results against a real running Prometheus, or
whether Grafana's dashboard schema version renders every panel exactly as
intended - that part depends on your own verification once this is live,
the same as Phase 8's Argo CD Application or Phase 9's canary did.
