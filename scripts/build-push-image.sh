#!/usr/bin/env bash
set -euo pipefail
REGION=$(terraform -chdir=infra/terraform output -raw region)
ACCOUNT=$(terraform -chdir=infra/terraform output -raw account_id)
REPO="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/vision-scale-bench"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
docker build -t vision-scale-bench:latest -f training/Dockerfile .
docker tag vision-scale-bench:latest "${REPO}:latest"
docker push "${REPO}:latest"
echo "${REPO}" > .ecr_repo
echo "Pushed ${REPO}:latest"
