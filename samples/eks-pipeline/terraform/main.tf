# =============================================================================
# Korvet Customer POC - EKS Infrastructure
# =============================================================================
# Deploys:
# - VPC with public/private subnets
# - EKS cluster with node groups for Redis and workloads
# - S3 bucket for tiered storage
# - IAM roles for IRSA (Korvet and Spark S3 access)
# - Redis Enterprise Operator via Helm
# =============================================================================

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# =============================================================================
# VPC
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "korvet-poc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # Cost savings for POC
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# =============================================================================
# Common Tags
# =============================================================================
locals {
  tags = {
    Project       = "korvet-customer-poc"
    Environment   = "poc"
    skip_deletion = "yes"
    owner         = var.owner
  }
}

# =============================================================================
# EKS Cluster
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "korvet-poc"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    # Node group for Redis Enterprise (memory-optimized)
    redis = {
      instance_types = ["r6i.xlarge"] # 4 vCPU, 32GB RAM
      min_size       = 3
      max_size       = 3
      desired_size   = 3

      labels = {
        "node-type" = "redis"
      }

      taints = [{
        key    = "redis-enterprise"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    # Node group for Korvet, Logstash, Spark
    workloads = {
      instance_types = ["m5.xlarge"] # 4 vCPU, 16GB RAM
      min_size       = 2
      max_size       = 5
      desired_size   = 3

      labels = {
        "node-type" = "workloads"
      }
    }
  }

  enable_irsa = true

  tags = local.tags
}

# =============================================================================
# S3 Bucket for Tiered Storage
# =============================================================================
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "korvet_data" {
  bucket = "korvet-poc-${var.region}-${random_id.bucket_suffix.hex}"

  tags = merge(local.tags, {
    Name = "korvet-poc-data"
  })
}

resource "aws_s3_bucket_versioning" "korvet_data" {
  bucket = aws_s3_bucket.korvet_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# IAM Policy for S3 Access
# =============================================================================
resource "aws_iam_policy" "korvet_s3" {
  name = "korvet-poc-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.korvet_data.arn,
          "${aws_s3_bucket.korvet_data.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# IRSA for Korvet
# =============================================================================
module "korvet_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "korvet-poc-s3-access"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["korvet:korvet"]
    }
  }

  role_policy_arns = {
    s3_access = aws_iam_policy.korvet_s3.arn
  }
}

# =============================================================================
# IRSA for Spark
# =============================================================================
module "spark_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "korvet-poc-spark-s3-access"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["spark:spark"]
    }
  }

  role_policy_arns = {
    s3_access = aws_iam_policy.korvet_s3.arn
  }
}



# =============================================================================
# NOTE: Kubernetes resources (namespaces, Helm releases) are deployed
# separately after EKS is created. See ../k8s/ directory.
# =============================================================================
