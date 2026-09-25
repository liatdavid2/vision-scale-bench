from __future__ import annotations

import json
import os
import platform
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT / "results"
FRONTEND_DIST = ROOT / "ui" / "frontend" / "dist"
RESULTS.mkdir(exist_ok=True)

app = FastAPI(title="Vision Scale Bench API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000", "http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class RunRequest(BaseModel):
    profile: str = "budget"

class Job:
    def __init__(self, platform_name: str):
        self.id = str(uuid.uuid4())
        self.platform = platform_name
        self.status = "queued"
        self.started_at: Optional[float] = None
        self.finished_at: Optional[float] = None
        self.logs: List[str] = []
        self.return_code: Optional[int] = None
        self.error: Optional[str] = None

    def as_dict(self):
        return {
            "id": self.id,
            "platform": self.platform,
            "status": self.status,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "return_code": self.return_code,
            "error": self.error,
            "logs": self.logs[-500:],
        }

jobs: Dict[str, Job] = {}
lock = threading.Lock()


def _cmd_for(platform_name: str) -> List[str]:
    is_windows = platform.system().lower().startswith("win")
    if platform_name == "eks":
        if is_windows:
            return ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "scripts" / "run-eks-benchmark.ps1")]
        return ["bash", str(ROOT / "scripts" / "run-eks-benchmark.sh")]
    if platform_name == "sagemaker":
        if is_windows:
            return ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "scripts" / "run-sagemaker-benchmark.ps1")]
        return ["python", str(ROOT / "scripts" / "run_sagemaker_benchmark.py"), "--all"]
    raise ValueError(platform_name)


def _run_job(job: Job):
    job.status = "running"
    job.started_at = time.time()
    cmd = _cmd_for(job.platform)
    job.logs.append("$ " + " ".join(cmd))
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=os.environ.copy(),
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            job.logs.append(line.rstrip())
        job.return_code = proc.wait()
        job.status = "completed" if job.return_code == 0 else "failed"
        if job.return_code != 0:
            job.error = f"Benchmark exited with code {job.return_code}"
    except Exception as exc:
        job.status = "failed"
        job.error = str(exc)
        job.logs.append(f"ERROR: {exc}")
    finally:
        job.finished_at = time.time()


def _load_results():
    rows = []
    for path in sorted(RESULTS.glob("*.json")):
        if path.name == "comparison.json":
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            data["_file"] = path.name
            rows.append(data)
        except Exception:
            pass
    return rows

@app.get("/api/health")
def health():
    return {"ok": True, "project": "vision-scale-bench"}

@app.post("/api/run/{platform_name}")
def run_benchmark(platform_name: str, request: RunRequest):
    if platform_name not in {"eks", "sagemaker"}:
        raise HTTPException(404, "Unknown platform")
    if request.profile != "budget":
        raise HTTPException(400, "Only the budget profile is enabled in this demo")
    with lock:
        if any(j.status in {"queued", "running"} for j in jobs.values()):
            raise HTTPException(409, "Another benchmark is already running")
        job = Job(platform_name)
        jobs[job.id] = job
    threading.Thread(target=_run_job, args=(job,), daemon=True).start()
    return job.as_dict()

@app.get("/api/jobs")
def list_jobs():
    return [j.as_dict() for j in sorted(jobs.values(), key=lambda x: x.started_at or 0, reverse=True)]

@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job.as_dict()

@app.get("/api/results")
def results():
    return _load_results()

@app.get("/api/results/comparison")
def comparison():
    p = RESULTS / "comparison.json"
    if not p.exists():
        return {"runs": _load_results()}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"runs": _load_results()}

@app.get("/{path:path}")
def spa(path: str):
    # Production mode: FastAPI serves the built React app.
    candidate = FRONTEND_DIST / path
    if path and candidate.is_file():
        return FileResponse(candidate)
    index = FRONTEND_DIST / "index.html"
    if index.exists():
        return FileResponse(index)
    raise HTTPException(404, "React build not found. Run npm install && npm run build in ui/frontend.")
