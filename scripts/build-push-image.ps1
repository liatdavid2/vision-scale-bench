$ErrorActionPreference = "Stop"
$region = terraform -chdir=infra/terraform output -raw region
$account = terraform -chdir=infra/terraform output -raw account_id
$repo = "$account.dkr.ecr.$region.amazonaws.com/vision-scale-bench"
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
docker build -t vision-scale-bench:latest -f training/Dockerfile .
docker tag vision-scale-bench:latest "${repo}:latest"
docker push "${repo}:latest"
Set-Content -Path .ecr_repo -Value $repo
Write-Host "Pushed ${repo}:latest"
