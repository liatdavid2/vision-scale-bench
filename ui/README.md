# Real UI — React + FastAPI + Docker Compose

This project does **not** use Streamlit.

- `frontend/`: React + Vite, served by Nginx
- `backend/`: FastAPI orchestration API
- Nginx proxies `/api/*` to the backend
- `POST /api/run/eks`: runs 2 workers, then 4 workers on EKS
- `POST /api/run/sagemaker`: runs 2 instances, then 4 SageMaker instances
- `GET /api/jobs/{id}`: status + live logs
- `GET /api/results`: benchmark JSON results

## Start the UI

If AWS credentials are stored in environment variables, they are passed into the backend container automatically. Otherwise copy `.env.example` to `.env` and fill the credentials locally.

```bash
docker compose up --build
```

Open:

```text
http://localhost:3000
```

The frontend is exposed on port 3000. FastAPI is also available directly on port 8000 for debugging.

## Stop the local UI

```bash
docker compose down
```

`docker compose down` only stops the **local UI containers**. It does not destroy AWS infrastructure. Use the project's destroy script / Terraform teardown for AWS resources.
