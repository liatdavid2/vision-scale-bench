#!/usr/bin/env bash
set -euo pipefail
mkdir -p results
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-1}}
CLUSTER_NAME=${EKS_CLUSTER_NAME:-vision-scale-bench}
INSTANCE_TYPE=${EKS_GPU_INSTANCE_TYPE:-g4dn.xlarge}
FALLBACK_SPOT_RATE=${EKS_GPU_SPOT_FALLBACK_RATE:-0.30}

scale_down() {
  echo "=== Scaling GPU worker group to 0 to stop GPU compute cost ==="
  terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=0" >/dev/null || true
}
trap scale_down EXIT

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
REPO=${ECR_REPO:-$(cat .ecr_repo)}

# NVIDIA device plugin exposes nvidia.com/gpu to Kubernetes pods.
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system --set gfd.enabled=false >/dev/null

SPOT_RATE=$(aws ec2 describe-spot-price-history \
  --region "$REGION" \
  --instance-types "$INSTANCE_TYPE" \
  --product-descriptions "Linux/UNIX" \
  --max-items 20 \
  --query 'SpotPriceHistory[0].SpotPrice' --output text 2>/dev/null || true)
if [ -z "$SPOT_RATE" ] || [ "$SPOT_RATE" = "None" ]; then SPOT_RATE="$FALLBACK_SPOT_RATE"; fi
echo "Estimated current ${INSTANCE_TYPE} Spot rate used for cost display: $${SPOT_RATE}/instance-hour"

for N in 2 4; do
  echo "=== EKS GPU benchmark: ${N} x ${INSTANCE_TYPE} (NVIDIA T4) ==="
  START=$(date +%s)
  terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=${N}"
  for i in $(seq 1 90); do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')
    GPU=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | grep -c '^1$' || true)
    [ "$READY" -ge "$N" ] && [ "$GPU" -ge "$N" ] && break
    sleep 10
  done
  kubectl get nodes -L node.kubernetes.io/instance-type
  kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu

  helm upgrade --install vision-bench charts/vision-benchmark \
    --set trainer.replicas="$N" \
    --set trainer.epochs=1 \
    --set trainer.maxTrainSamples=5000 \
    --set trainer.maxTestSamples=1000 \
    --set image.repository="$REPO" --set image.tag=latest

  kubectl rollout status statefulset/vision-trainer --timeout=420s || true
  echo "Waiting for RESULT_JSON from rank 0..."
  RESULT=""
  for i in $(seq 1 120); do
    RESULT=$(kubectl logs vision-trainer-0 2>/dev/null | grep 'RESULT_JSON=' | tail -1 | sed 's/^.*RESULT_JSON=//' || true)
    [ -n "$RESULT" ] && break
    sleep 5
  done
  END=$(date +%s)
  if [ -z "$RESULT" ]; then kubectl logs vision-trainer-0 || true; exit 1; fi
  python scripts/save_result.py --json "$RESULT" --platform eks --workers "$N" \
    --job-seconds "$((END-START))" --instance-hourly-rate "$SPOT_RATE" --cluster-hourly-rate 0.10
  helm uninstall vision-bench >/dev/null 2>&1 || true
done
python scripts/compare_results.py
