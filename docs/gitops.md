# Phase 8 — Argo CD / GitOps

## What changed from Phase 6

Phase 6 deployed the app by running `scripts/deploy-to-eks.sh` by hand from
your laptop. That script still exists and still works, but from this phase
on it's no longer the intended path for `main` - Argo CD is:

```
git push to main
      │
      ▼
GitHub Actions (Phase 7): lint → test → scan → build → Trivy → push to ECR
      │
      ▼
update-gitops job: bumps gitops/environments/dev/values.yaml's image.tag,
                    commits, pushes - THIS commit is the actual GitOps event
      │
      ▼
Argo CD (running in-cluster, polling this repo): notices the values.yaml
                    change, runs `helm template` with it, diffs against
                    what's actually running, applies the difference
      │
      ▼
EKS: pods roll to the new image tag
```

No `kubectl apply`, no SSH, no laptop involved in a normal deploy from here
on - the only thing a developer does is `git push`.

## Why a Helm chart now, not raw manifests

`k8s/eks/*.yaml` (Phase 6) still exists and still works for manual
deployment, but Argo CD needs a single templated source it can render
per-environment - `helm/kubeforge/` is that source. One notable design
choice: `templates/deployment.yaml` ranges over a `services` map in
`values.yaml` rather than having three near-identical copies of a
Deployment template (one per service) - see that file's own comments. This
was checked by actually rendering it (this sandbox couldn't reach
`get.helm.sh`, same restriction hit for `terraform`/`kind`/`docker` in
earlier phases, so a small Go-template-subset renderer was built
specifically to prove this against the real `values.yaml` rather than
eyeball it) - confirmed it correctly produces 5 documents (api
Deployment+Service, frontend Deployment+Service, worker Deployment only,
matching `worker.createService: false`).

## One-time setup

### 1. Install Argo CD

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd
kubectl get pods -n argocd    # wait for everything Running
```

### 2. Get the initial admin password and log in

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Open `https://localhost:8080`, username `admin`, the password above.

### 3. Point the Application at your actual repo

Edit `gitops/environments/dev/application.yaml` - replace
`REPLACE-WITH-YOUR-GITHUB-USERNAME` with your real GitHub username.

### 4. Bootstrap the Application (one-time, manual - this is the only
`kubectl apply` you should ever need for this app from here on)

```bash
kubectl apply -f gitops/environments/dev/application.yaml
```

### 5. Confirm the secret still exists

Argo CD's chart deliberately does **not** create `kubeforge-secrets` (see
`helm/kubeforge/templates/NOTES.txt`). If Phase 6's secret is still there
from before, nothing to do. If it's missing:
```bash
scripts/create-eks-secret.sh
```

## How each GitOps requirement is actually satisfied

| Requirement | How |
|---|---|
| Automated synchronization | `syncPolicy.automated` in `application.yaml` - Argo CD polls the repo and applies changes with no manual trigger |
| Health status | `kubectl get application kubeforge-dev -n argocd` or the UI - Argo CD tracks per-resource health (Deployment rollout status, etc.), not just "applied successfully" |
| Drift detection | `selfHeal: true` - if `kubectl edit` changes anything live, Argo CD notices the live state no longer matches Git and reverts it automatically |
| Rollback | `argocd app history kubeforge-dev` then `argocd app rollback kubeforge-dev <id>` - or just `git revert` the GitOps commit, which Argo CD then syncs to automatically like any other change |

## Verifying a real deploy end-to-end

```bash
git commit --allow-empty -m "test: trigger a GitOps deploy"
git push
```
Watch the Actions tab for `update-gitops` to complete, then:
```bash
kubectl get application kubeforge-dev -n argocd -w
```
Watch it move through `OutOfSync` → `Syncing` → `Synced`, `Healthy`.

```bash
kubectl get pods -n kubeforge -o jsonpath='{.items[*].spec.containers[*].image}'
```
Should show the new commit SHA in every image reference.

## Drift detection, actually demonstrated

```bash
kubectl scale deployment/api -n kubeforge --replicas=5
```
Within Argo CD's next reconcile (default a few minutes, or force it: `argocd app sync kubeforge-dev`), it should scale back to 2 - Git says `replicas: 2`, and `selfHeal: true` means Git wins, not whatever a manual `kubectl` command just did.

## Staging and production

Both directories exist (`gitops/environments/staging`,
`gitops/environments/production`) but aren't wired to an Argo CD
Application yet - their `image.registry` is empty because
`infrastructure/terraform/environments/{staging,production}` haven't been
applied. Production's values file also has a note worth taking seriously:
full `selfHeal` automation for production is a deliberate decision, not
something to inherit from dev's config by default - most real setups
require manual sync approval for production even when dev is fully
automated.
