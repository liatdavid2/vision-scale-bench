#!/usr/bin/env bash
set -euo pipefail
mkdir -p results
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}
CLUSTER_NAME=${EKS_CLUSTER_NAME:-vision-scale-bench}
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
REPO=${ECR_REPO:-$(cat .ecr_repo)}
for N in 2 4; do
  echo "=== Scaling EKS workers to ${N} ==="
  terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=${N}"
  for i in $(seq 1 60); do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')
    [ "$READY" -ge "$N" ] && break
    sleep 10
  done
  START=$(date +%s)
  helm upgrade --install vision-bench charts/vision-benchmark \
    --set trainer.replicas="$N" \
    --set image.repository="$REPO" --set image.tag=latest
  kubectl rollout status statefulset/vision-trainer --timeout=300s || true
  echo "Waiting for RESULT_JSON from rank 0..."
  RESULT=""
  for i in $(seq 1 180); do
    RESULT=$(kubectl logs vision-trainer-0 2>/dev/null | grep 'RESULT_JSON=' | tail -1 | sed 's/^.*RESULT_JSON=//' || true)
    [ -n "$RESULT" ] && break
    sleep 5
  done
  END=$(date +%s)
  if [ -z "$RESULT" ]; then echo "No result found"; kubectl logs vision-trainer-0 || true; exit 1; fi
  python scripts/save_result.py --json "$RESULT" --platform eks --workers "$N" --job-seconds "$((END-START))"
  helm uninstall vision-bench || true
  kubectl delete pod -l app.kubernetes.io/name=vision-trainer --ignore-not-found=true || true
done
python scripts/compare_results.py
