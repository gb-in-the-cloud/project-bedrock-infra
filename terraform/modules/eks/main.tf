# EKS Module — project-bedrock-cluster
#
# Creates:
#   - EKS cluster:    project-bedrock-cluster (K8s 1.34)
#   - Node group:     project-bedrock-node-group (private subnets)
#   - IAM role:       project-bedrock-cluster-role  (least privilege)
#   - IAM role:       project-bedrock-node-role     (least privilege)
#   - KMS key:        Secrets encryption at rest
#   - OIDC provider:  Enables IRSA (IAM Roles for Service Accounts)
#   - IAM user:       bedrock-dev-view (developer read-only access)
#   - Access entries: Modern EKS auth — no aws-auth ConfigMap
#
# IAM Least Privilege:
#   Cluster role — only AmazonEKSClusterPolicy (minimum to run EKS)
#   Node role    — EKSWorkerNode + ECRReadOnly + EKS_CNI (minimum for nodes)
#   Dev user     — AmazonEKSViewPolicy (read kubectl, cannot modify)
#   CI/CD        — AmazonEKSClusterAdminPolicy (full access for pipelines)


#--- IAM: Cluster Role ---#
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

#---IAM: Node Group Role ---#
resource "aws_iam_role" "nodes" {
  name = "${var.project_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_cloudwatch" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_access_entry" "name" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.cluster.arn
  type          = "STANDARD"

  lifecycle {
    ignore_changes = [cluster_name]
  }

  tags = { Name = "${var.project_name}-cicd-access"
  }

}
# ── IAM: Developer User — bedrock-dev-view ────────────────────────────────────
# Required by assessment. Read-only kubectl access.
# Developers can inspect and debug but cannot modify cluster resources.
resource "aws_iam_user" "dev_view" {
  name = "bedrock-dev-view"
  path = "/"

  tags = { Purpose = "developer-read-only-eks-access" }
}

# ── KMS: Secrets Encryption ───────────────────────────────────────────────────
# By default Kubernetes Secrets are base64-encoded in etcd (not encrypted).
# KMS envelope encryption protects them at rest.
resource "aws_kms_key" "eks" {
  description             = "KMS key for ${var.project_name} EKS Secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = { Name = "${var.project_name}-eks-kms" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ── Security Group: Cluster ───────────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = { Name = "${var.project_name}-cluster-sg" }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true # kubectl from inside VPC
    endpoint_public_access  = true # kubectl from GitHub Actions runner
  }

  # Control plane audit logging — required for security and compliance
  enabled_cluster_log_types = [
    "api",           # All API server calls
    "audit",         # Security audit trail
    "authenticator", # Authentication events
    "controllerManager",
    "scheduler"
  ]

  # Encrypt Kubernetes Secrets at rest with KMS
  encryption_config {
    provider { key_arn = aws_kms_key.eks.arn }
    resources = ["secrets"]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = { Name = "${var.project_name}-cluster" }
}

# ── OIDC Provider ─────────────────────────────────────────────────────────────
# Required for IRSA (IAM Roles for Service Accounts).
# Allows pods to assume IAM roles without storing credentials anywhere.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = { Name = "${var.project_name}-oidc" }
}

# ── EKS Managed Node Group ────────────────────────────────────────────────────
# AWS manages node lifecycle, AMI updates, and draining.
# AL2023 is required from EKS 1.33+ (Amazon Linux 2 deprecated).
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids # Always private

  instance_types = [var.node_instance_type]
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1 # Replace one node at a time
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni,
  ]

  tags = { Name = "${var.project_name}-node-group" }
}

# ── EKS Access Entry: CI/CD Admin ────────────────────────────────────────────
resource "aws_eks_access_entry" "cicd" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.cicd_iam_arn
  type          = "STANDARD"

  tags = { Name = "${var.project_name}-cicd-access" }
}

resource "aws_eks_access_policy_association" "cicd" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.cicd_iam_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope { type = "cluster" }
}

# ── EKS Access Entry: Developer Read-Only ────────────────────────────────────
# bedrock-dev-view gets view-only kubectl access.
# Cannot create, update, or delete resources — least privilege for developers.
resource "aws_eks_access_entry" "dev_view" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.cluster.arn
  type          = "STANDARD"

  lifecycle {
    ignore_changes = [cluster_name]
  }

  tags = { Name = "${var.project_name}-dev-view-access"
  }

}

resource "aws_eks_access_policy_association" "dev_view" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_user.dev_view.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope { type = "cluster" }
}