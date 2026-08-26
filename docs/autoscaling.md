# Phase 10 — Autoscaling

Two independent scaling mechanisms, and why both are necessary - HPA alone
isn't enough:

```
Traffic increases
      │
      ▼
api pods' CPU crosses 70% (HPA's target)
      │
      ▼
HPA scales api: 2 → up to 10 pods (helm/kubeforge/templates/hpa.yaml)
      │
      ▼
Do the existing 2 EC2 nodes have room for the new pods?
      │
      ├── Yes → new pods schedule immediately, done
      │
      └── No → new pods sit Pending
                      │
                      ▼
              Cluster Autoscaler notices the Pending pods
                      │
                      ▼
              Adds EC2 nodes (up to node group's max - Phase 5's
              eks_node_max_size, currently 3 for dev)
                      │
                      ▼
              Pending pods schedule once the new node joins
```

Without Cluster Autoscaler, HPA can decide to scale to 10 pods and simply
never succeed past whatever the existing nodes can physically hold - this
was flagged as a planned refinement all the way back in Phase 1's
architecture doc, and this is the phase that actually builds it.

## One-time setup

### 1. metrics-server (HPA has nothing to read CPU usage from without this - EKS doesn't ship it by default)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system
```
Wait for `1/1`, then sanity check it's actually reporting real numbers:
```bash
kubectl top pods -n kubeforge
```

### 2. Cluster Autoscaler

No Terraform changes were needed for node group tagging - confirmed via
AWS's own docs that EKS managed node groups are automatically tagged for
Cluster Autoscaler discovery the moment they're created. Only the IRSA role
(so the Cluster Autoscaler pod itself has AWS permissions) needed adding -
`infrastructure/terraform/environments/dev`'s `irsa_cluster_autoscaler`
module, already applied if you've re-run `terraform apply` since this phase.

```bash
ROLE_ARN=$(cd infrastructure/terraform/environments/dev && terraform output -raw cluster_autoscaler_role_arn)
CLUSTER_NAME=kubeforge-dev

kubectl create serviceaccount cluster-autoscaler -n kube-system --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate serviceaccount cluster-autoscaler -n kube-system \
  eks.amazonaws.com/role-arn="${ROLE_ARN}" --overwrite

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName="${CLUSTER_NAME}" \
  --set awsRegion=us-east-1 \
  --set rbac.serviceAccount.create=false \
  --set rbac.serviceAccount.name=cluster-autoscaler

kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
```

Confirm it's actually seeing the node group (not just running):
```bash
kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler | grep -i "kubeforge-dev"
```

### 3. Install k6

```bash
winget install k6.k6
```
(Chocolatey alternative: `choco install k6`. No admin rights on this machine: download the Windows binary directly from k6's GitHub releases and call it via its full path from Git Bash - the same `~/bin`-on-PATH pattern already used for `kind` and the `kubectl argo-rollouts` plugin.)

## Running a real load test

Open **two terminals**.

**Terminal 1** - watch scaling happen live:
```bash
kubectl get hpa,pods -n kubeforge -w
```

**Terminal 2** - generate real load against the real ALB:
```bash
kubectl get ingress kubeforge -n kubeforge   # grab the ADDRESS if you don't have it handy
k6 run -e BASE_URL=http://<your-alb-hostname> scripts/load-tests/api-load-test.js
```

The test runs ~10 minutes total (see the `stages` in the script). Watch
Terminal 1 during this - you're looking for:
- `HPA` `TARGETS` column climbing toward/past `70%`
- `Deployment`/`Rollout` replica count increasing
- Any pods stuck `Pending` (the actual trigger for Cluster Autoscaler to add a node)
- `kubectl get nodes -w` in a third terminal, if you want to watch node count specifically

## Recording real numbers - the actual point of this phase

Section 30 of `docs/architecture.md` is explicit: never invent a metric. k6
prints real numbers when the run finishes - `http_req_duration` (p50/p95/p99),
`http_reqs` (total + rate), `http_req_failed`. Save this output:

```bash
k6 run -e BASE_URL=http://<your-alb-hostname> scripts/load-tests/api-load-test.js | tee /tmp/load-test-results.txt
```

Alongside that, note down from Terminal 1's live watch:
- What request rate (roughly) coincided with the first HPA scale-up event
- How many pods it topped out at
- Whether Cluster Autoscaler added a node, and how long that took start to finish
- How long scale-back-down took once the k6 ramp-down stage started

That combination - "at ~N req/s, api scaled from 2 to M pods in T seconds,
and P95 latency stayed at Xms" - is a real, defensible resume line. A
comprehensive, multi-scenario load testing pass (stress tests, soak tests,
formal thresholds) is Phase 18's job - this is the first real proof the
mechanism works at all, not the final word on capacity planning.
