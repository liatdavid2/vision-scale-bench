#!/usr/bin/env bash
set -euo pipefail
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}

echo "Cleaning Crossplane-created AWS resources directly (works even with 0 EKS workers)..."
if [ -f .s3_bucket ]; then
  BUCKET=$(cat .s3_bucket)
  aws s3 rm "s3://${BUCKET}" --recursive --region "$REGION" 2>/dev/null || true
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null || true
fi
if [ -f .ecr_repo_name ]; then
  REPO=$(cat .ecr_repo_name)
else
  REPO=vision-scale-bench
fi
aws ecr delete-repository --repository-name "$REPO" --force --region "$REGION" 2>/dev/null || true

terraform -chdir=infra/terraform destroy -auto-approve -var="worker_count=0"
rm -f .s3_bucket .ecr_repo .ecr_repo_name
echo "Destroyed EKS/VPC/GPU node group/IAM and removed benchmark S3/ECR resources."
