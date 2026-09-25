#!/usr/bin/env bash
set -euo pipefail
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}
CLUSTER_NAME=${EKS_CLUSTER_NAME:-vision-scale-bench}

echo "=== 1/5 Terraform init ==="
terraform -chdir=infra/terraform init

echo "=== 2/5 Bootstrap EKS with one temporary GPU node ==="
terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=1"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null

echo "=== 3/5 Install Crossplane and create S3 + ECR ==="
bash scripts/install-crossplane.sh

echo "=== 4/5 Build and push CUDA/PyTorch training image ==="
bash scripts/build-push-image.sh

echo "=== 5/5 Scale temporary GPU node group to zero ==="
terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=0"

echo "Setup complete. GPU worker count is now 0. Open http://localhost:7475 and run either benchmark."
