#!/usr/bin/env bash
set -euo pipefail

# The real-AWS equivalent of scripts/create-k8s-secret.sh from Phase 4.
# Differences from the local version:
#   - DATABASE_URL is built from the REAL RDS endpoint + the password RDS
#     itself generated and stored in Secrets Manager (Phase 5's
#     manage_master_user_password = true) - fetched here, never typed
#     anywhere, never stored in this repo.
#   - REDIS_URL still points at the in-cluster Redis Service (no
#     ElastiCache module exists yet - see k8s/eks/10-redis.yaml).
#   - RABBITMQ_URL still comes from the same root .env as every previous
#     phase - one cloud broker, one place its URL lives, unchanged since
#     Phase 3.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infrastructure/terraform/environments/dev"
ENV_FILE="$ROOT_DIR/.env"

command -v aws >/dev/null || { echo "AWS CLI is not installed"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is not installed"; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE - copy .env.example to .env and set RABBITMQ_URL first." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [ -z "${RABBITMQ_URL:-}" ]; then
  echo "RABBITMQ_URL is not set in $ENV_FILE" >&2
  exit 1
fi

echo "==> Reading RDS connection details from Terraform state"
cd "$TF_DIR"
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)         # host:port
RDS_DB_NAME=$(terraform output -raw rds_db_name)
RDS_USERNAME=$(terraform output -raw rds_master_username)
RDS_SECRET_ARN=$(terraform output -raw rds_master_user_secret_arn)

echo "==> Fetching the RDS master password from Secrets Manager"
json_field() {
  JSON_INPUT="$1" JSON_KEY="$2" node -e "console.log(JSON.parse(process.env.JSON_INPUT)[process.env.JSON_KEY])"
}
# Extract the region from the ARN itself (field 4 of a colon-separated ARN)
# rather than trusting the AWS CLI's ambient default region config. A full
# ARN does NOT automatically route this particular API call to the right
# regional endpoint - if the CLI's configured default region differs from
# where the secret actually lives, this fails with ResourceNotFoundException
# even though the ARN is completely correct. Same fix pattern already used
# in build-and-push-ecr.sh for the ECR registry region.
SECRET_REGION=$(echo "$RDS_SECRET_ARN" | cut -d: -f4)
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --region "$SECRET_REGION" \
  --secret-id "$RDS_SECRET_ARN" \
  --query SecretString --output text)
RDS_PASSWORD=$(json_field "$SECRET_JSON" "password")

# AWS-generated RDS passwords can contain characters like @ : / % # that are
# meaningful delimiters inside a postgres://user:password@host/db URL - an
# unescaped one breaks Node's URL parser entirely (this is exactly what
# happened: pg's connection-string parser uses the built-in URL class, which
# threw "Invalid URL" the moment the password contained one of these).
# encodeURIComponent handles this correctly, and the values are passed to
# node via environment variables rather than interpolated into the -e source
# string directly - that distinction matters here specifically because this
# password is randomly generated and could contain shell-meaningful
# characters (backticks, $(), quotes) that would be a command-injection risk
# if interpolated into the script text instead of passed as data.
url_encode() {
  VALUE="$1" node -e "console.log(encodeURIComponent(process.env.VALUE))"
}
ENCODED_USERNAME=$(url_encode "$RDS_USERNAME")
ENCODED_PASSWORD=$(url_encode "$RDS_PASSWORD")
DATABASE_URL="postgres://${ENCODED_USERNAME}:${ENCODED_PASSWORD}@${RDS_ENDPOINT}/${RDS_DB_NAME}"

echo "==> Applying namespace (idempotent) and creating kubeforge-secrets"
kubectl create namespace kubeforge --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic kubeforge-secrets \
  --namespace kubeforge \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=REDIS_URL="redis://redis:6379" \
  --from-literal=RABBITMQ_URL="$RABBITMQ_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

# Belt and suspenders: never let the fetched password sit in this script's
# environment longer than it has to.
unset RDS_PASSWORD DATABASE_URL

echo "kubeforge-secrets created/updated in namespace kubeforge (EKS)"
