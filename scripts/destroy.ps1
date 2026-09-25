$ErrorActionPreference = "Continue"
helm uninstall vision-bench 2>$null
kubectl delete -f crossplane/resources/ --ignore-not-found=true
Start-Sleep -Seconds 20
terraform -chdir=infra/terraform destroy -auto-approve
Write-Host "Destroyed EKS/VPC/workers/IAM. Check Cost Explorer after billing data settles."
