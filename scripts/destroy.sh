#!/usr/bin/env bash
set -euo pipefail
helm uninstall vision-bench 2>/dev/null || true
kubectl delete -f crossplane/resources/ --ignore-not-found=true || true
for i in $(seq 1 60); do
  N=$(kubectl get repositories.ecr.aws.upbound.io,buckets.s3.aws.upbound.io --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$N" = "0" ] && break
  sleep 5
done
terraform -chdir=infra/terraform destroy -auto-approve
echo "Destroyed EKS/VPC/workers/IAM. Check Cost Explorer after billing data settles."
