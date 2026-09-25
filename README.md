# Vision Scale Bench

A deliberately small, low-cost benchmark for **distributed computer-vision training on AWS**.
It runs the same PyTorch workload on:

- **Amazon EKS / Kubernetes** with **2 and 4 worker nodes**
- **Amazon SageMaker Training** with **2 and 4 training instances**
- **Helm** to package/deploy the Kubernetes training workload
- **Crossplane** to declaratively provision shared AWS resources (S3 + ECR)
- **Terraform** only for the bootstrap layer that must exist before Crossplane can run (VPC, EKS, node group, IAM)

The benchmark is intentionally short: **CIFAR-10 + ResNet-18, small subset, 2 epochs**. The goal is not SOTA accuracy; it is to measure orchestration overhead, distributed scaling, throughput, training time and cost.

## Suggested GitHub repository name

**`vision-scale-bench`**

Other good names: `distributed-vision-aws-benchmark`, `eks-sagemaker-vision-bench`, `vision-training-scale-lab`.

## What is compared

| Platform | Size | Training |
|---|---:|---|
| EKS | 2 workers | PyTorch DDP / `torchrun` |
| EKS | 4 workers | PyTorch DDP / `torchrun` |
| SageMaker | 2 instances | PyTorch DDP / `torchrun` |
| SageMaker | 4 instances | PyTorch DDP / `torchrun` |

Metrics written by the training code:

- wall-clock training seconds
- images / second
- epoch time
- validation accuracy
- worker count
- backend (`gloo` for CPU, `nccl` for GPU)
- samples processed

The orchestration scripts additionally record infrastructure/job time and estimated compute cost.

## Cost target: about $1 or less for a short demo

The default **budget** profile uses CPU Spot workers on EKS and small on-demand SageMaker CPU instances, with only a few thousand CIFAR-10 images and 2 epochs. It avoids the expensive AWS items that usually ruin tiny demos:

- **no NAT Gateway**
- **no load balancer**
- **no always-on endpoint**
- **no RDS / OpenSearch / managed Prometheus**
- EKS and workers are destroyed after the benchmark

The EKS control plane itself is billed per cluster-hour, and worker EC2, EBS and public IPv4 are separate. SageMaker training is billed for the training instances while the job runs. Therefore **$1 is a target, not a guarantee**: startup time, Spot availability, Region and price changes matter. The scripts use hard runtime caps and print estimated cost from measured duration.

> Important: do **not** create 2 or 4 separate EKS clusters for this benchmark. One EKS cluster with **2 vs 4 worker nodes** measures distributed training scaling. Multiple independent clusters mainly measure multi-cluster operations and add control-plane cost.

## Automatic dataset download

Yes. `training/train.py` uses `torchvision.datasets.CIFAR10(download=True)`. If `/data/cifar-10-batches-py` already exists, Torchvision reuses it; otherwise the dataset is downloaded automatically. Each training node keeps its own small local cache, which avoids shared-filesystem complexity for a ~170 MB dataset.

## Architecture

```text
                         +-------------------+
                         |   CIFAR-10        |
                         | auto-download     |
                         +---------+---------+
                                   |
                   same Docker image / same code
                                   |
                 +-----------------+-----------------+
                 |                                   |
        +--------v---------+                +--------v----------+
        | Amazon EKS       |                | SageMaker Training|
        | Kubernetes       |                |                   |
        +--------+---------+                +---------+---------+
                 |                                    |
        +--------+--------+                  +--------+--------+
        | 2 workers       |                  | 2 instances     |
        | 4 workers       |                  | 4 instances     |
        +--------+--------+                  +--------+--------+
                 |                                    |
                 +---------------+--------------------+
                                 |
                       results/*.json
                                 |
                       React + FastAPI UI

Bootstrap: Terraform -> EKS
Platform packages: Helm -> Crossplane + benchmark chart
Cloud resources: Crossplane -> ECR + S3
```

## Prerequisites

- AWS CLI authenticated
- Terraform >= 1.6
- Docker
- kubectl
- Helm 3
- Python 3.10+
- AWS quota allowing 4 small EC2 workers and 4 SageMaker training instances

Default region: `eu-central-1`. The Terraform bootstrap pins EKS Kubernetes **1.36**, which is currently in standard support.

## Local UI with Docker Compose

The normal local startup path is Docker Compose. It starts two containers:

- `frontend` — React build served by Nginx on `http://localhost:3000`
- `backend` — FastAPI plus AWS CLI, Terraform, kubectl and Helm on port `8000`

First bootstrap the temporary AWS infrastructure and install Crossplane / push the training image once (see the setup scripts below). Then start the UI:

```powershell
docker compose up --build
```

Open **http://localhost:3000**. Nginx proxies `/api` to FastAPI, and the two UI buttons launch the real benchmark orchestration.

Stop only the local UI:

```powershell
docker compose down
```

To destroy the AWS resources after the demo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\destroy.ps1
```

### One-time AWS bootstrap (PowerShell)

```powershell
cd infra\terraform
terraform init
terraform apply -auto-approve -var="worker_count=2"
cd ..\..

powershell -ExecutionPolicy Bypass -File .\scripts\install-crossplane.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build-push-image.ps1
```

The backend refreshes its own EKS kubeconfig using `aws eks update-kubeconfig`, so Docker Compose does not depend on your host kubeconfig. AWS credentials can be passed from shell environment variables or from a local `.env` copied from `.env.example`. Never commit real credentials.

## Real UI: React + FastAPI + Docker Compose

The project includes a real web application under `ui/`; **Streamlit is not used**.

The home page has two independent run buttons:

- **Run EKS / Kubernetes benchmark** — run with 2 workers, then 4 workers.
- **Run SageMaker benchmark** — run with 2 training instances, then 4 training instances.

While a benchmark runs, the UI shows status and live orchestration logs. Completed runs are loaded from `results/*.json` and displayed with training time, images/second, validation accuracy, end-to-end job time, and estimated compute cost.

The backend intentionally binds to `127.0.0.1`: its run endpoints execute local Terraform, Helm, kubectl, AWS CLI and SageMaker orchestration commands, so it should not be exposed publicly without authentication.

### What each part of the project does

**PyTorch DDP** — the distributed-training engine. Each worker processes a different portion of each training step and DDP synchronizes model gradients across the workers. It is the common training mechanism in both benchmark paths.

**EKS / Kubernetes** — the Kubernetes execution path. The benchmark runs the DDP training workload with 2 workers and then with 4 workers, measuring scale-out performance, orchestration overhead and estimated cost.

**SageMaker Training — 2 vs 4 instances** — the managed AWS comparison path. SageMaker runs the same training container with 2 and then 4 instances and shuts down the training compute after each job completes.

**Helm Chart** — packages the Kubernetes training workload. Helm values control the Docker image, 2/4 worker replicas, epochs, dataset subset size and DDP service discovery.

**Crossplane** — manages shared AWS resources from Kubernetes YAML. In this project it provisions the S3 bucket for artifacts/results and the ECR repository for the training image.

**Terraform** — bootstraps the infrastructure that must exist before Crossplane can run: VPC, EKS, worker node group and IAM/IRSA roles. It also provides the final infrastructure teardown path.

## What Crossplane does

Crossplane is installed into EKS using its official Helm repository. AWS providers are installed for S3 and ECR. The AWS provider authenticates using **IRSA**, so static AWS keys are not stored inside Kubernetes.

Crossplane resources in `crossplane/resources/` create:

- ECR repository for the training image
- small S3 results/artifact bucket

Terraform creates the Crossplane IRSA role because this role must exist before the AWS Crossplane providers can authenticate. This is the normal bootstrap boundary: Crossplane cannot provision the Kubernetes cluster in which it has not yet been installed.

## Helm

`charts/vision-benchmark` deploys a headless Service + StatefulSet. StatefulSet pod ordinals become DDP node ranks:

```text
vision-trainer-0 -> rank 0 (master)
vision-trainer-1 -> rank 1
vision-trainer-2 -> rank 2
vision-trainer-3 -> rank 3
```

Hard pod anti-affinity spreads replicas across worker nodes, so 2 replicas means 2 nodes and 4 replicas means 4 nodes.

## Budget profile

Defaults are intentionally small:

```text
Dataset       CIFAR-10
Model         ResNet-18
Train subset  8,000 images
Test subset   2,000 images
Epochs        2
Batch/worker  64
EKS compute   c6a.large Spot (fallback families configured)
SageMaker     ml.c5.xlarge on-demand
Runs          2 workers, then 4 workers
```

For an even cheaper smoke test:

```powershell
helm upgrade --install vision-bench charts/vision-benchmark `
  --set trainer.replicas=2 `
  --set trainer.maxTrainSamples=4000 `
  --set trainer.maxTestSamples=1000 `
  --set trainer.epochs=1 `
  --set image.repository=$env:ECR_REPO `
  --set image.tag=latest
```

## Why a small dataset is still useful

For this project the research question is **systems performance**, not model quality. A small fixed dataset makes repeated 2-vs-4-node tests inexpensive and reveals something important: for tiny workloads, scaling can be worse because synchronization and startup overhead dominate. That is a legitimate benchmark result.

The UI therefore separates:

1. **training-only time**
2. **end-to-end job time**
3. **throughput**
4. **2 -> 4 worker speedup**
5. **parallel efficiency** = speedup / 2
6. **estimated cost**
7. **cost per 1,000 training images**

## Safety rails

- SageMaker `MaxRuntimeInSeconds=900`
- EKS worker count is capped at 4 by Terraform validation
- no NAT Gateway
- no Kubernetes Service type LoadBalancer
- all resources tagged `Project=vision-scale-bench`
- `destroy.ps1` deletes Crossplane resources before destroying EKS

## Results directory

Example output:

```json
{
  "platform": "eks",
  "workers": 4,
  "epochs": 2,
  "train_samples": 8000,
  "training_seconds": 83.1,
  "images_per_second": 192.5,
  "val_accuracy": 0.36
}
```

Real numbers depend on AWS placement, image-pull time and instance availability.
