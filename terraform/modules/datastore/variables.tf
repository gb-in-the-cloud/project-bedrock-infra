variable "project_name"       { type = string }
variable "project_tag"         { type = string }
variable "environment"         { type = string }
variable "vpc_id"              { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "eks_node_sg_id"     {
  type        = string
  description = "Security group ID of EKS worker nodes — allows DB ingress from nodes only"
}