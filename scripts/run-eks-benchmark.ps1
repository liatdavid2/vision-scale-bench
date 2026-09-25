$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force results | Out-Null
$repo = (Get-Content .ecr_repo -Raw).Trim()
foreach ($n in @(2,4)) {
  Write-Host "=== Scaling EKS workers to $n ==="
  terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=$n"
  for ($i=0; $i -lt 60; $i++) {
    $ready = (kubectl get nodes --no-headers 2>$null | Select-String " Ready ").Count
    if ($ready -ge $n) { break }
    Start-Sleep -Seconds 10
  }
  $start = Get-Date
  helm upgrade --install vision-bench charts/vision-benchmark --set trainer.replicas=$n --set image.repository=$repo --set image.tag=latest
  $result = $null
  for ($i=0; $i -lt 180; $i++) {
    $line = kubectl logs vision-trainer-0 2>$null | Select-String "RESULT_JSON=" | Select-Object -Last 1
    if ($line) { $result = ($line.ToString() -replace '^.*RESULT_JSON=', ''); break }
    Start-Sleep -Seconds 5
  }
  if (-not $result) { kubectl logs vision-trainer-0; throw "No RESULT_JSON found" }
  $seconds = ((Get-Date) - $start).TotalSeconds
  python scripts/save_result.py --json $result --platform eks --workers $n --job-seconds $seconds
  helm uninstall vision-bench
}
python scripts/compare_results.py
