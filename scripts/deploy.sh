#!/usr/bin/env bash
# deploy.sh — project-bedrock
# Usage: ./scripts/deploy.sh [init|plan|apply|destroy]

set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
STATE_BUCKET="${TF_STATE_BUCKET:-project-bedrock-tfstate-alt-soe-tin-025-0007}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()   { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2; exit 1; }

check_deps() {
  command -v terraform &>/dev/null || error "terraform not installed"
  command -v aws &>/dev/null       || error "aws CLI not installed"
  aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured"
  [[ -f "$TF_DIR/terraform.tfvars" ]] || error "terraform.tfvars missing — cp terraform.tfvars.example terraform.tfvars"
}

tf_init() {
  cd "$TF_DIR"
  terraform init \
    -backend-config="bucket=$STATE_BUCKET" \
    -backend-config="region=$AWS_REGION"
}

tf_plan() {
  check_deps
  log "Planning..."
  cd "$TF_DIR"
  terraform init -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$AWS_REGION" -reconfigure > /dev/null
  terraform fmt -recursive -check || terraform fmt -recursive
  terraform validate
  terraform plan -var-file=terraform.tfvars -out=tfplan
  log "Plan saved to tfplan ✓"
}

tf_apply() {
  tf_plan
  read -rp "Apply? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { log "Cancelled."; exit 0; }
  cd "$TF_DIR"
  terraform apply tfplan
  CLUSTER=$(terraform output -raw cluster_name)
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER"
  kubectl get nodes
  kubectl create namespace retail-app --dry-run=client -o yaml | kubectl apply -f -
  log "Deploy complete ✓"
}

tf_destroy() {
  check_deps
  # Confirm FIRST before touching anything
  echo -e "${RED}"
  read -rp "  Type 'destroy' to confirm: " CONFIRM
  echo -e "${NC}"
  [[ "$CONFIRM" != "destroy" ]] && { log "Cancelled."; exit 0; }

  # Then clean up Kubernetes resources
  log "Removing Kubernetes ingress and ALB..."
  kubectl delete ingress retail-store-ingress \
    -n retail-app --ignore-not-found=true 2>/dev/null || true
  helm uninstall aws-load-balancer-controller \
    -n kube-system 2>/dev/null || true
  kubectl delete namespace retail-app \
    --ignore-not-found=true 2>/dev/null || true

  log "Waiting 60s for ALB deprovisioning..."
  sleep 60

  # Then destroy infrastructure
  tf_init > /dev/null
  cd "$TF_DIR"
  terraform destroy -var-file=terraform.tfvars -auto-approve
  log "Destroy complete ✓"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
case "${1:-}" in
  init)    check_deps; tf_init ;;
  plan)    tf_plan ;;
  apply)   tf_apply ;;
  destroy) tf_destroy ;;
  *)       echo "Usage: $0 [init|plan|apply|destroy]"; exit 1 ;;
esac