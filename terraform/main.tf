# =============================================================================
# project-bedrock — Root Module
#
# Entry point for all infrastructure. Calls child modules in order:
#   networking → eks → observability → budget → serverless
#
# Naming conventions (graded — do not change):
#   EKS Cluster  : project-bedrock-cluster
#   VPC Tag      : project-bedrock-vpc
#   IAM User     : bedrock-dev-view
#   S3 Bucket    : bedrock-assets-[student-id]
#   Lambda       : bedrock-asset-processor
#   App Namespace: retail-app
#   Tag          : Project: tinyuka-2025-capstone
# =============================================================================

terraform {
  required_version = ">= 1.11.0"

  # ── Remote State ─────────────────────────────────────────────────────────
  # bucket, region passed via -backend-config at init time.
  # use_lockfile prevents concurrent applies corrupting state (Terraform 1.11+).
  # No DynamoDB table needed — native S3 locking is sufficient.
  backend "s3" {
    key          = "bedrock/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ── Provider ────────────────────────────────────────────────────────────────
# default_tags applies Project: tinyuka-2025-capstone to ALL resources.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_tag
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# ── Data Sources ─────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Locals ───────────────────────────────────────────────────────────────────
locals {
  account_id = data.aws_caller_identity.current.account_id

  # CI/CD identity — defaults to whoever runs terraform apply
  cicd_arn = var.cicd_iam_arn != "" ? var.cicd_iam_arn : data.aws_caller_identity.current.arn
}

# =============================================================================
# MODULE: Networking
# Creates project-bedrock-vpc with public/private subnets across 2 AZs.
# Single NAT Gateway (cost guardrail — assessed requirement).
# =============================================================================
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  project_tag          = var.project_tag
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# =============================================================================
# MODULE: EKS
# Provisions project-bedrock-cluster (K8s 1.34 — oldest active standard support).
# IAM roles follow least-privilege. Developer IAM user: bedrock-dev-view.
# =============================================================================
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  project_tag        = var.project_tag
  environment        = var.environment
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  cicd_iam_arn       = local.cicd_arn
}

# =============================================================================
# MODULE: Observability
# CloudWatch log groups, Fluent Bit IRSA role, Container Insights role.
# =============================================================================
module "observability" {
  source = "./modules/observability"

  project_name       = var.project_name
  project_tag        = var.project_tag
  environment        = var.environment
  cluster_name       = module.eks.cluster_name
  cluster_oidc_url   = module.eks.cluster_oidc_url
  cluster_oidc_arn   = module.eks.cluster_oidc_arn
  log_retention_days = var.log_retention_days
}

# =============================================================================
# MODULE: Budget
# $20/month cap scoped to Project: tinyuka-2025-capstone tag.
# Alerts at 80% actual and 100% forecasted spend.
# =============================================================================
module "budget" {
  source = "./modules/budget"

  project_name    = var.project_name
  project_tag     = var.project_tag
  budget_limit    = var.budget_limit_usd
  alert_threshold = var.budget_alert_threshold_percent
  alert_email     = var.budget_alert_email
}

# =============================================================================
# MODULE: Serverless
# S3 bucket (bedrock-assets-[student-id]), Lambda (bedrock-asset-processor),
# EventBridge rule that triggers Lambda when objects land in S3.
# =============================================================================
module "serverless" {
  source = "./modules/serverless"

  project_name = var.project_name
  project_tag  = var.project_tag
  environment  = var.environment
  student_id   = var.student_id
  cluster_name = module.eks.cluster_name
  dev_view_user_arn = module.eks.dev_user_arn
}

# =============================================================================
# MODULE: Datastore
# Managed AWS data services replacing in-cluster databases.
# Runs AFTER networking and EKS — needs subnets and node security group.
# =============================================================================
module "datastore" {
  source = "./modules/datastore"

  project_name       = var.project_name
  project_tag        = var.project_tag
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  eks_node_sg_id     = module.eks.node_security_group_id
}