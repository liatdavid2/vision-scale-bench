# Vision Scale Bench

A deliberately short **GPU-only distributed computer-vision benchmark on AWS**. The same PyTorch/CUDA training image is executed through two AWS paths and scaled from **2 GPUs to 4 GPUs**:

- **Amazon EKS / Kubernetes:** 2 → 4 `g4dn.xlarge` Spot nodes, one NVIDIA T4 per node.
- **Amazon SageMaker Training:** 2 → 4 `ml.g4dn.xlarge` instances using Managed Spot Training.

The workload is intentionally small so a portfolio/demo run can finish quickly and target roughly **$1 or less for both benchmark buttons together**. That is a target, not a billing guarantee: Spot prices, provisioning time, quotas and AWS pricing can change.

## Benchmark workload

- Dataset: **CIFAR-10**, downloaded automatically by Torchvision when missing.
- Model: **ResNet-18**, adapted to 32×32 CIFAR images.
- Train subset: **5,000 images**.
- Test subset: **1,000 images**.
- Epochs: **1** by default.
- Batch size: **128 per GPU**.
- Distributed engine: **PyTorch DDP / torchrun**, NCCL on GPU.

This is a scaling/cost experiment, not an accuracy benchmark. A tiny workload may even show that 4 GPUs are less efficient than 2 because synchronization and startup overhead dominate; that is a valid benchmark result.

## What the two UI buttons do

### Run EKS / Kubernetes GPU Benchmark

1. Scale the EKS managed node group to **2 × `g4dn.xlarge` Spot** nodes.
2. Install/use the NVIDIA Kubernetes device plugin.
3. Deploy the Helm training workload with **2 DDP workers / 2 T4 GPUs**.
4. Save time, throughput, accuracy and estimated cost.
5. Scale to **4 GPU nodes**, repeat the exact same workload with **4 DDP workers / 4 T4 GPUs**.
6. Save the comparison.
7. **Automatically scale the GPU node group to 0**, including on failure, so GPU compute does not remain running.

The EKS control plane remains until `scripts\destroy.cmd` so the project can continue to use the bootstrapped AWS environment. The control plane has its own AWS charge even while GPU worker count is zero, so destroy the demo when finished.

### Run SageMaker GPU Benchmark

1. Start a SageMaker Managed Spot Training job with **2 × `ml.g4dn.xlarge`**.
2. Run the same PyTorch DDP image and workload.
3. Save metrics and artifact to the Crossplane-created S3 bucket.
4. Repeat with **4 × `ml.g4dn.xlarge`**.
5. SageMaker training compute stops when each job ends.

A hard runtime/wait cap is configured to prevent an accidental long-running job.

## What each technology does

**PyTorch DDP** — the distributed training engine. Every GPU process trains on a different shard of the batch and synchronizes gradients with the other workers. Both EKS and SageMaker use the same DDP code, making the comparison meaningful.

**EKS / Kubernetes** — the self-managed orchestration path. Kubernetes schedules one training pod per GPU node. We compare 2 versus 4 T4 GPUs and measure the scaling benefit and orchestration overhead.

**SageMaker Training** — the managed AWS alternative. It runs the same container with 2 and then 4 GPU instances. Managed Spot is enabled to reduce demo cost.

**Helm Chart** — packages the Kubernetes training workload. Helm values control replica count, image, epochs, sample count, GPU request/limit and DDP service discovery.

**Crossplane** — runs in Kubernetes and creates the shared AWS **S3 bucket and ECR repository** declaratively from YAML resources.

**Terraform** — bootstraps what must exist before Crossplane: **VPC, EKS, the GPU node group, IAM/IRSA roles and SageMaker execution role**. It is also the final teardown mechanism.

## Architecture

```text
                        CIFAR-10
                    auto-download if absent
                            |
                 same CUDA/PyTorch image
                            |
             +--------------+--------------+
             |                             |
      EKS / Kubernetes              SageMaker Training
             |                             |
      2 T4 -> 4 T4 GPUs             2 T4 -> 4 T4 GPUs
      Spot g4dn.xlarge              Managed Spot
             |                             |
             +--------------+--------------+
                            |
                     results/*.json
                            |
                    React + FastAPI UI

Terraform  -> VPC + EKS + IAM bootstrap
Helm       -> Crossplane + DDP workload
Crossplane -> S3 + ECR
```

## Local UI — Docker Compose

The local application is a real **React + Nginx frontend** and **FastAPI backend**. Streamlit is not used.

Ports used by this repository:

- UI: `http://localhost:7475`
- Backend/Swagger: `http://localhost:7474/docs`

Start from Windows **CMD**:

```cmd
docker compose up --build
```

Health check:

```cmd
curl http://localhost:7474/api/health
curl http://localhost:7475/api/health
```

Both should return:

```json
{"ok":true,"project":"vision-scale-bench"}
```

Stop only the local containers:

```cmd
docker compose down
```

## AWS credentials and Docker safety

Copy `.env.example` to `.env` and fill your local credentials if they are not already supplied another way:

```text
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=
AWS_DEFAULT_REGION=eu-central-1
```

For a normal IAM access key, `AWS_SESSION_TOKEN` can remain empty.

`.env` is excluded by both `.gitignore` **and `.dockerignore`**. The backend image does not bake the secret file into the image. Docker Compose passes only the configured AWS environment variables to the backend container at runtime. Never commit `.env`.

Check Git ignores it:

```cmd
git check-ignore -v .env
```

## One-time AWS setup

First keep Docker Compose running. Then from a second CMD window run:

```cmd
scripts\setup.cmd
```

The setup performs:

1. `terraform init`
2. creates the EKS bootstrap with **one temporary `g4dn.xlarge` GPU Spot node**
3. installs Crossplane via Helm
4. Crossplane creates S3 + ECR
5. builds/pushes the CUDA/PyTorch training image
6. scales the temporary GPU node group back to **0**

The temporary one-node bootstrap keeps setup cost lower than bootstrapping with 2 or 4 nodes.

> `docker-compose.yml` mounts the local Docker socket into the backend container so the setup script can build/push the training image. This is intended for local development only; access to the Docker socket is privileged and should not be exposed to untrusted code.

## Run the experiments

Open:

```text
http://localhost:7475
```

Then use the independent buttons:

- **Run EKS / Kubernetes GPU Benchmark** — 2 GPUs, then 4 GPUs, then auto-scale GPU workers to 0.
- **Run SageMaker GPU Benchmark** — 2 GPU instances, then 4 GPU instances, Managed Spot.

The UI displays live orchestration logs plus:

- training time
- images/second
- validation accuracy
- end-to-end/job time
- estimated compute cost
- 2→4 speedup
- parallel efficiency

## Cost target

The project is tuned for a **short demo around $1 or less total** across both benchmark buttons:

```text
CIFAR-10 train subset: 5,000
CIFAR-10 test subset:  1,000
ResNet-18
1 epoch

EKS:       2 -> 4 x g4dn.xlarge Spot (NVIDIA T4)
SageMaker: 2 -> 4 x ml.g4dn.xlarge Managed Spot (NVIDIA T4)
```

The EKS script queries the current EC2 Spot price at run time for its UI estimate and falls back to `EKS_GPU_SPOT_FALLBACK_RATE` only if that lookup fails. SageMaker uses `SAGEMAKER_GPU_REFERENCE_RATE` only as a reference estimate; actual Managed Spot billing can be lower and should be verified in AWS Cost Explorer.

The estimate is **not a spending guarantee** because provisioning time and Spot pricing vary. The important safeguards are: one epoch, small data subset, Managed Spot, EKS Spot, runtime caps, and automatic EKS GPU scale-down.

## Destroy AWS resources when finished

From CMD:

```cmd
scripts\destroy.cmd
```

This removes the Crossplane-created S3/ECR resources and then runs Terraform destroy for EKS/VPC/IAM. Do not confuse this with `docker compose down`, which only stops the local UI/backend and does **not** stop AWS billing.

## Repository structure

```text
vision-scale-bench/
├── docker-compose.yml
├── .env.example
├── .dockerignore
├── charts/vision-benchmark/       # Helm GPU workload
├── crossplane/                    # S3 + ECR
├── infra/terraform/               # VPC + EKS GPU nodes + IAM
├── scripts/
│   ├── setup.cmd
│   ├── setup.sh
│   ├── destroy.cmd
│   ├── destroy.sh
│   ├── run-eks-benchmark.sh
│   └── run_sagemaker_benchmark.py
├── training/                      # CUDA/PyTorch DDP + CIFAR-10
├── results/
└── ui/
    ├── frontend/                  # React + Nginx
    └── backend/                   # FastAPI orchestration API
```

## UI-driven setup and cleanup

The local UI now controls the AWS lifecycle directly:

- **Setup AWS Infrastructure** runs `scripts/setup.sh` in the backend container. It bootstraps Terraform/EKS/IAM, installs Crossplane, creates S3/ECR, builds and pushes the GPU training image, then scales the GPU node group back to zero.
- **Destroy AWS Infrastructure** runs `scripts/destroy.sh` after a confirmation prompt. It removes the benchmark S3/ECR resources and executes `terraform destroy`.

The `.cmd` scripts remain available only as recovery/fallback paths; normal use does not require them.
