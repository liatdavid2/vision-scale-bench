FROM python:3.12-slim

ARG TERRAFORM_VERSION=1.13.3
ARG KUBECTL_VERSION=v1.36.0
ARG HELM_VERSION=v3.19.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl unzip git jq groff less docker.io \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN arch="$(dpkg --print-architecture)"; \
    if [ "$arch" = "amd64" ]; then aws_arch="x86_64"; else aws_arch="aarch64"; fi; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# Terraform
RUN arch="$(dpkg --print-architecture)"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip" -o /tmp/terraform.zip && \
    unzip -q /tmp/terraform.zip -d /usr/local/bin && rm /tmp/terraform.zip

# kubectl
RUN arch="$(dpkg --print-architecture)"; \
    if [ "$arch" = "amd64" ]; then karch="amd64"; else karch="arm64"; fi; \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${karch}/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Helm
RUN arch="$(dpkg --print-architecture)"; \
    if [ "$arch" = "amd64" ]; then harch="amd64"; else harch="arm64"; fi; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${harch}.tar.gz" -o /tmp/helm.tgz && \
    tar -xzf /tmp/helm.tgz -C /tmp && mv "/tmp/linux-${harch}/helm" /usr/local/bin/helm && \
    rm -rf /tmp/helm.tgz "/tmp/linux-${harch}"

WORKDIR /workspace
COPY ui/backend/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY . /workspace

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/workspace \
    AWS_DEFAULT_REGION=eu-central-1

EXPOSE 8000
CMD ["uvicorn", "ui.backend.app:app", "--host", "0.0.0.0", "--port", "8000"]
