provider "aws" { region = var.aws_region }

data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name = var.cluster_name
  cidr = "10.42.0.0/16"
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = ["10.42.1.0/24", "10.42.2.0/24"]
  enable_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true
  map_public_ip_on_launch = true
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  tags = { Project = var.cluster_name }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name = var.cluster_name
  cluster_version = "1.36"
  cluster_endpoint_public_access = true
  enable_irsa = true
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    bench = {
      instance_types = var.instance_types
      capacity_type  = "SPOT"
      ami_type       = "AL2023_x86_64_NVIDIA"
      min_size       = var.worker_count == 0 ? 0 : 1
      max_size       = 4
      desired_size   = var.worker_count
      disk_size      = 30
      labels = { workload = "vision-bench" }
      tags = { Project = var.cluster_name }
    }
  }
  tags = { Project = var.cluster_name }
}

# Crossplane runs inside EKS, so Terraform provides only the bootstrap IAM role.
data "aws_iam_policy_document" "crossplane_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect = "Allow"
    principals {
      type = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = ["system:serviceaccount:crossplane-system:provider-aws-*"]
    }
  }
}

resource "aws_iam_role" "crossplane" {
  name = "${var.cluster_name}-crossplane"
  assume_role_policy = data.aws_iam_policy_document.crossplane_assume.json
  tags = { Project = var.cluster_name }
}
resource "aws_iam_role_policy_attachment" "crossplane_s3" {
  role = aws_iam_role.crossplane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "crossplane_ecr" {
  role = aws_iam_role.crossplane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role" "sagemaker" {
  name = "${var.cluster_name}-sagemaker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "sagemaker.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = var.cluster_name }
}
resource "aws_iam_role_policy_attachment" "sagemaker_ecr" {
  role = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "sagemaker_s3" {
  role = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
