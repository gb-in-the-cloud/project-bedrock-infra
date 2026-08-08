
# Root Variables

# ── Identity & Tagging ───────────────────────────────────────────────────────

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "project-bedrock"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase, alphanumeric, and hyphens only."
  }
}

variable "project_tag" {
  description = "Project tag for AWS resources. Used in default_tags."
  type    = string
  default = "tinyuka-2025-capstone"
}

variable "environment" {
  description = "Deployment environment. Used in resource names and tags."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be prod, staging, or dev."
  }
}

variable "aws_region" {
  description = "AWS region. Assessment requires us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner name for tagging and cost attribution."
  type        = string
  default     = "oluwagbenga-george-oyewole"
}

variable "student_id" {
  description = "Student ID for tagging."
  type = string
}

variable "cicd_iam_arn" {
  description = <<-EOT
    IAM ARN of the CI/CD user (GitHub Actions).
    Gets cluster-admin access so pipelines can deploy to EKS.
    Defaults to the identity running terraform apply if empty.
  EOT
  type    = string
  default = ""
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs — one per AZ. Hosts NAT Gateway and ALBs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs — one per AZ. Hosts EKS worker nodes."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "AZs to deploy into. Minimum 2 required for high availability."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required."
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

variable "eks_cluster_version" {
  type    = string
  default = "1.34"

  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.eks_cluster_version)
    error_message = "EKS version must be 1.34 or above. 1.33 is expiring; 1.32 and below are end-of-life."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes. t3.medium = 2 vCPU, 4GB RAM."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum worker nodes. 1 ensures system pods always have a node."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum worker nodes for autoscaling."
  type        = number
  default     = 4
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch log retention in days.
    30 = balanced cost vs debugging window.
    Without a limit, logs accumulate and costs grow unbounded.
  EOT
  type    = number
  default = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value."
  }
}

# ── Budget ────────────────────────────────────────────────────────────────────

variable "budget_limit_usd" {
  description = "Monthly budget cap in USD. Assessment example: $20."
  type        = string
  default     = "20"
}

variable "budget_alert_threshold_percent" {
  description = "Send email alert at this % of budget. 80% gives time to act before hitting the cap."
  type        = number
  default     = 80

  validation {
    condition     = var.budget_alert_threshold_percent > 0 && var.budget_alert_threshold_percent <= 100
    error_message = "Threshold must be between 1 and 100."
  }
}

variable "budget_alert_email" {
  description = <<-EOT
    Email for budget alerts.
    AWS sends a confirmation email — click it or alerts won't fire.
  EOT
  type = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.budget_alert_email))
    error_message = "Must be a valid email address."
  }
}
