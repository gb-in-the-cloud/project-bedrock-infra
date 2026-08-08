output "cluster_endpoint" {
  description = "HTTPS endpoint for the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name: project-bedrock-cluster."
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region the cluster is deployed in."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the VPC: project-bedrock-vpc."
  value       = module.networking.vpc_id
}

output "assets_bucket_name" {
  description = "S3 assets bucket name: bedrock-assets-[student-id]."
  value       = module.serverless.assets_bucket_name
}

# ── Networking ────────────────────────────────────────────────────────────────

output "public_subnet_ids" {
  description = "Public subnet IDs — ALBs and NAT Gateway live here."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS worker nodes live here."
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_ip" {
  description = <<-EOT
    Public IP of the single NAT Gateway.
    Add this IP to external service allowlists (e.g. MongoDB Atlas).
  EOT
  value       = module.networking.nat_gateway_ip
}

# ── EKS ───────────────────────────────────────────────────────────────────────

output "eks_cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = module.eks.cluster_version
}

output "eks_node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "bedrock_dev_view_arn" {
  description = "ARN of the bedrock-dev-view IAM user (developer read-only access)."
  value       = module.eks.dev_user_arn
}

# ── Observability ─────────────────────────────────────────────────────────────

output "cloudwatch_log_group" {
  description = "CloudWatch log group for EKS cluster logs."
  value       = module.observability.log_group_name
}

output "fluent_bit_role_arn" {
  description = "IRSA role ARN for Fluent Bit — pass to Helm chart install."
  value       = module.observability.fluent_bit_role_arn
}

# ── Serverless ────────────────────────────────────────────────────────────────

output "lambda_function_name" {
  description = "Lambda function name: bedrock-asset-processor."
  value       = module.serverless.lambda_function_name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule that triggers Lambda on S3 object creation."
  value       = module.serverless.eventbridge_rule_name
}

# ── Developer Convenience ─────────────────────────────────────────────────────

output "kubectl_config_command" {
  description = "Run this command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "retail_app_namespace_command" {
  description = "Create the retail-app namespace after cluster is ready."
  value       = "kubectl create namespace retail-app"
}

output "deployment_summary" {
  description = "Full deployment summary."
  value       = <<-EOT
              project-bedrock Deployment Summary                
  
    cluster_name      : ${module.eks.cluster_name}
    cluster_endpoint  : ${module.eks.cluster_endpoint}
    region            : ${var.aws_region}
    vpc_id            : ${module.networking.vpc_id}
    assets_bucket     : ${module.serverless.assets_bucket_name}
    nat_gateway_ip    : ${module.networking.nat_gateway_ip}

    kubectl:
    aws eks update-kubeconfig \
   --region ${var.aws_region} \
   --name ${module.eks.cluster_name}
  
  EOT
}
