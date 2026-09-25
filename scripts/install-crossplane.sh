#!/usr/bin/env bash
set -euo pipefail
ROLE_ARN=$(terraform -chdir=infra/terraform output -raw crossplane_role_arn)
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update
helm upgrade --install crossplane crossplane-stable/crossplane --namespace crossplane-system --create-namespace
kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=240s
sed "s|CROSSPLANE_ROLE_ARN|${ROLE_ARN}|g" crossplane/providers.yaml | kubectl apply -f -
echo "Waiting for Crossplane AWS providers..."
for i in $(seq 1 60); do
  if kubectl get providers 2>/dev/null | grep -q 'provider-aws-s3.*True.*True' && kubectl get providers 2>/dev/null | grep -q 'provider-aws-ecr.*True.*True'; then break; fi
  sleep 5
done
kubectl apply -f crossplane/providerconfig.yaml
kubectl apply -f crossplane/resources/ecr.yaml
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" crossplane/resources/s3.yaml | kubectl apply -f -
echo "Waiting for ECR repository and S3 bucket..."
for i in $(seq 1 60); do
  R=$(kubectl get repository.ecr.aws.upbound.io vision-scale-bench -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [ "$R" = "True" ] && break
  sleep 5
done
kubectl get providers
kubectl get repositories.ecr.aws.upbound.io,buckets.s3.aws.upbound.io
# Persist the Crossplane-created resource names so SageMaker can run even while EKS GPU nodes are scaled to zero.
BUCKET=$(kubectl get bucket.s3.aws.upbound.io vision-scale-bench-results -o jsonpath='{.metadata.annotations.crossplane\.io/external-name}' 2>/dev/null || true)
REPO_NAME=$(kubectl get repository.ecr.aws.upbound.io vision-scale-bench -o jsonpath='{.metadata.annotations.crossplane\.io/external-name}' 2>/dev/null || true)
[ -n "$BUCKET" ] && echo "$BUCKET" > .s3_bucket
[ -n "$REPO_NAME" ] && echo "$REPO_NAME" > .ecr_repo_name
