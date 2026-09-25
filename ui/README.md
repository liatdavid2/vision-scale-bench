# UI

Real React + FastAPI UI; no Streamlit.

Run locally with Docker Compose from the repository root:

```cmd
docker compose up --build
```

Open `http://localhost:7475`. FastAPI Swagger is at `http://localhost:7474/docs`.

The EKS button runs 2 -> 4 NVIDIA T4 GPU workers and automatically scales GPU workers to zero afterward. The SageMaker button runs 2 -> 4 `ml.g4dn.xlarge` Managed Spot Training instances.
