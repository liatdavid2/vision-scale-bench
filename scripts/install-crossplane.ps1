$ErrorActionPreference = "Stop"
$role = terraform -chdir=infra/terraform output -raw crossplane_role_arn
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>$null
helm repo update
helm upgrade --install crossplane crossplane-stable/crossplane --namespace crossplane-system --create-namespace
kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=240s
(Get-Content crossplane/providers.yaml -Raw).Replace("CROSSPLANE_ROLE_ARN", $role) | kubectl apply -f -

for ($i=0; $i -lt 60; $i++) {
  $providers = kubectl get providers 2>$null | Out-String
  if ($providers -match 'provider-aws-s3\s+True\s+True' -and $providers -match 'provider-aws-ecr\s+True\s+True') { break }
  Start-Sleep -Seconds 5
}
kubectl apply -f crossplane/providerconfig.yaml
kubectl apply -f crossplane/resources/
for ($i=0; $i -lt 60; $i++) {
  $repo = kubectl get repository.ecr.aws.upbound.io vision-scale-bench -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>$null
  if ($repo -eq 'True') { break }
  Start-Sleep -Seconds 5
}
kubectl get providers
kubectl get repositories.ecr.aws.upbound.io,buckets.s3.aws.upbound.io
