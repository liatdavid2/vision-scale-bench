$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "Installing/updating Python UI dependencies..."
python -m pip install -r ui/backend/requirements.txt

if (-not (Test-Path "ui/frontend/node_modules")) {
  Write-Host "Installing React dependencies..."
  Push-Location ui/frontend
  npm install
  Pop-Location
}

Write-Host "Building React UI..."
Push-Location ui/frontend
npm run build
Pop-Location

Write-Host "Starting Vision Scale Bench at http://localhost:8000"
python -m uvicorn ui.backend.app:app --host 127.0.0.1 --port 8000
