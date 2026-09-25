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
kubectl apply -f crossplane/resources/
echo "Waiting for ECR repository..."
for i in $(seq 1 60); do
  R=$(kubectl get repository.ecr.aws.upbound.io vision-scale-bench -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [ "$R" = "True" ] && break
  sleep 5
done
kubectl get providers
kubectl get repositories.ecr.aws.upbound.io,buckets.s3.aws.upbound.io
