# Phase 9 — Production Kubernetes Configuration

## What's new

| Addition | Where | What it actually does |
|---|---|---|
| Security contexts | `templates/_helpers.tpl` | Non-root (matches the Docker `USER node` from Phase 3, enforced again at the K8s level), read-only root filesystem, all Linux capabilities dropped, no privilege escalation |
| Startup probes | `templates/_helpers.tpl` | Liveness doesn't start evaluating until this succeeds once - see the comment in that file for the exact retry-timing math this is based on |
| Topology spread | `templates/_helpers.tpl` | Each service's 2 replicas prefer landing in different AZs, not the same node |
| RBAC | `templates/serviceaccount.yaml` | A dedicated ServiceAccount per service, granted zero permissions, with `automountServiceAccountToken: false` - see that file's comment for why "zero permissions" is the *correct* answer here, not a placeholder |
| NetworkPolicy | `templates/networkpolicy.yaml` | Default-deny baseline, then exactly the egress each service's real code actually needs - traced from `services/*/src`, not assumed |
| PodDisruptionBudget | `templates/pdb.yaml` | `minAvailable: 1` per service - a node drain can't take both replicas of one service down at once |
| Canary deployments | `templates/rollout.yaml` | `api` is now an Argo Rollout instead of a plain Deployment |

## One-time setup: install Argo Rollouts

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl get pods -n argo-rollouts
```

Optional but genuinely useful - the `kubectl argo-rollouts` plugin gives a live terminal dashboard for watching a canary progress:
```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```
(Windows: grab the `-windows-amd64.exe` asset from the same releases page instead.)

Argo CD needs to know how to display `Rollout` health too - if you're on a recent Argo CD version this is usually built in already; if `kubectl get application kubeforge-dev -n argocd` shows the app `Healthy` despite a Rollout stuck mid-canary, that's worth checking.

## Verified before shipping - and how, given the same limitation as every Terraform/Docker/kind phase before this

`helm` isn't reachable from the sandbox this was built in (same `host_not_allowed` restriction hit for `terraform`, `kind`, and `docker` in earlier phases). Rather than eyeball ~150 lines of Go template logic across 9 files, a small but genuinely functional renderer was built for the specific subset used here (`range`/`if`/`with`/`define`/`include`, `dict`, `toYaml`/`nindent`/`quote`) and every template was actually rendered against the real `values.yaml` and validated as real, parseable YAML:

- `deployment.yaml` → 3 documents (frontend Deployment+Service, worker Deployment only) - confirmed `api` is correctly excluded
- `rollout.yaml` → 2 documents (api Rollout+Service) - confirmed the canary `steps` render as alternating `setWeight`/`pause` entries matching `values.yaml`'s `canary.steps`
- `networkpolicy.yaml` → 5 documents - confirmed `frontend`'s policy has DNS-only egress (no redis/RDS/RabbitMQ rules, since it doesn't call any of them), `worker`'s policy correctly has no `ingress` block at all
- Confirmed the shared `_helpers.tpl` pod spec produces byte-identical security/probe/topology configuration whether it ends up wrapped in a `Deployment` (worker, frontend) or a `Rollout` (api) - the actual point of extracting it into one named template

This caught several real bugs in the renderer itself along the way (root-context resolution, quoted-string literals inside `dict(...)`, list vs. map `range`) - each one confirmed fixed by re-rendering, not just patched and assumed correct.

## Running an actual canary

```bash
# make some visible change - even just a comment - and push
git commit --allow-empty -m "test: trigger a canary rollout"
git push
```

Once Argo CD syncs the new image tag:
```bash
kubectl argo rollouts get rollout api -n kubeforge --watch
```
You should see it step through 5% → pause → 25% → pause → 50% → pause → 100%, each pause lasting 60 seconds (see `values.yaml`'s `canary.steps`).

**Abort a bad rollout mid-canary:**
```bash
kubectl argo rollouts abort api -n kubeforge
```
This immediately routes 100% of traffic back to the last known-good version - the actual point of canary in the first place: a bad deploy only ever gets a small fraction of real traffic before someone (or eventually something) notices and reverts.

## The trade-off worth understanding, not just the mechanism

This is "basic canary" - traffic weighting is approximated by the **ratio of canary-to-stable pod count**, not precise percentage-based routing at the load balancer itself. With `setWeight: 25` and 4 total desired pods, that's roughly 1 canary pod to 3 stable pods, and Kubernetes' normal per-pod Service load distribution does the rest. This is simple, requires no extra AWS-specific setup, and is genuinely how most teams start with Argo Rollouts.

The more precise alternative - actual weighted traffic splitting enforced by the ALB itself - needs the `argoproj-labs/rollouts-plugin-trafficrouter-alb` plugin, which manages real ALB listener rule weights directly. That's a legitimate next step, not implemented here, to keep this phase scoped to what's needed to demonstrate the concept correctly rather than adding a second AWS-specific controller before its trade-offs can be explained clearly.

**Also worth being upfront about**: these canary steps are purely time-based right now (`pause: {duration: 60s}`), not metrics-gated. A real production canary should automatically abort if error rate or latency regresses during a step - that needs an `AnalysisTemplate` querying a real metrics source, which doesn't exist yet (Prometheus arrives in Phase 11). This is flagged as a deliberate, temporary gap, not an oversight.

## NetworkPolicy - what it can't actually do, honestly

The RabbitMQ egress rule (`ipBlock: 0.0.0.0/0`, port `5671` only) is more permissive than the Redis or RDS rules, which are scoped to a specific pod or a specific VPC CIDR. This isn't a mistake - a managed cloud broker's IP address isn't stable or knowable in advance (DNS-based, provider-managed, can change). Plain Kubernetes NetworkPolicy has a real, well-known limit here: it operates at L3/L4 (IP + port), and it genuinely cannot express "only this specific external hostname" the way an application-layer firewall or an egress gateway could. Scoping to the specific port rather than leaving all egress open is the honest middle ground given that constraint - not a gap to silently paper over.
