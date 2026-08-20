# Phase 6 — EKS Deployment

This is the first phase where the app runs on the real EKS cluster from
Phase 5 instead of local `kind`. It reuses everything already built:
Phase 3's Dockerfiles, Phase 5's ECR repos and IAM, and a variant of Phase
4's manifests adapted for real infrastructure.

## What's different from Phase 4 (local kind)

| | Phase 4 (kind) | Phase 6 (real EKS) |
|---|---|---|
| Images | `kind load docker-image`, `:local` tag | Pushed to real ECR, real version tag |
| Postgres | In-cluster Deployment | **Real RDS** (Phase 5) |
| Redis | In-cluster Deployment | Still in-cluster - no ElastiCache module built yet |
| Ingress controller | ingress-nginx | **AWS Load Balancer Controller** (real ALB) |
| Secret creation | `create-k8s-secret.sh` | `create-eks-secret.sh` (fetches the real RDS password from Secrets Manager) |

## One-time: install the AWS Load Balancer Controller

This is a cluster addon, not application infrastructure - it's installed via
Helm directly against the cluster, not through Terraform. Terraform's job in
Phase 5/6 was only to create the IAM role (`aws_lb_controller_role_arn`
output) this controller needs; the controller itself is imperative, one-time,
per-cluster setup.

```bash
# 1. Get the values Terraform already created
cd infrastructure/terraform/environments/dev
ROLE_ARN=$(terraform output -raw aws_lb_controller_role_arn)
VPC_ID=$(terraform output -raw vpc_id_for_lb_controller)
cd ../../../..

# 2. Create the ServiceAccount, annotated with that IAM role (this is the
#    actual IRSA linkage - a pod running as this ServiceAccount can assume
#    the role via the EKS OIDC provider from Phase 5)
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

# 3. Install the controller via its official Helm chart
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=kubeforge-dev \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId="${VPC_ID}"

# 4. Confirm it's running before deploying anything that depends on it
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Deploying the app

```bash
# 1. Build and push real images to ECR (never :latest - see the script comments)
scripts/build-and-push-ecr.sh
# note the tag it prints, e.g. manual-20260817120000

# 2. Deploy everything, in the right order, to the real cluster
scripts/deploy-to-eks.sh manual-20260817120000
```

`deploy-to-eks.sh` handles the same secret-before-deployments ordering
gotcha from Phase 4, applies the manifests, and polls for the ALB's hostname
once the AWS Load Balancer Controller finishes provisioning it - which
genuinely takes a few minutes, since it's creating a real AWS Elastic Load
Balancer, not just a Kubernetes object.

## Why routes changed (`/tasks` → `/api/tasks`)

AWS's ALB has no equivalent to nginx-ingress's `rewrite-target` annotation -
it forwards whatever path it received, unmodified, to the target group. The
Phase 4 approach (Ingress strips `/api` before forwarding) simply doesn't
work the same way here. Rather than depend on ALB's newer `transforms`
annotation (real, but version-dependent and more moving parts than
necessary), the api's own routes now live under `/api` directly - see
`services/api/src/index.js`. This works identically regardless of which
ingress controller is in front of it, which is arguably the more portable
design regardless of AWS-specific limitations.

Health checks (`/health/live`, `/health/ready`) stay **unprefixed** and are
mounted at both paths - this is what both Kubernetes probes and the ALB's
own target group health check use, and it's the same path on both api and
frontend, so one Ingress-level `healthcheck-path` annotation covers both
backends without separate Ingress objects.

## Troubleshooting

- **ALB never gets a hostname**: `kubectl describe ingress kubeforge -n kubeforge` and `kubectl logs -n kube-system deployment/aws-load-balancer-controller` - almost always an IAM permission gap or the controller not finding tagged subnets (Phase 5's VPC module tags subnets with `kubernetes.io/role/elb` / `internal-elb` specifically for this).
- **Pods stuck `ImagePullBackOff`**: confirm the image tag in the rendered manifest actually exists in ECR (`aws ecr describe-images --repository-name kubeforge-api`) - a mismatch between what `build-and-push-ecr.sh` pushed and what `deploy-to-eks.sh` was told to deploy is the usual cause.
- **`/api/health/ready` shows `database: unreachable`**: check the RDS security group actually allows traffic from the EKS cluster's security group (Phase 5's `modules/rds` scopes ingress to exactly that) - and confirm `create-eks-secret.sh` ran successfully before the api pods started.
