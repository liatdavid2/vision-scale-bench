#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python -m pip install -r ui/backend/requirements.txt
if [ ! -d ui/frontend/node_modules ]; then
  (cd ui/frontend && npm install)
fi
(cd ui/frontend && npm run build)
echo "Starting Vision Scale Bench at http://localhost:8000"
python -m uvicorn ui.backend.app:app --host 127.0.0.1 --port 8000
