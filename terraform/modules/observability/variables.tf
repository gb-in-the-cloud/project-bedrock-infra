variable "project_name" { type = string }
variable "project_tag" { type = string }
variable "environment" { type = string }
variable "cluster_name" { type = string }
variable "cluster_oidc_url" { type = string }
variable "cluster_oidc_arn" { type = string }
variable "log_retention_days" {
  type    = number
  default = 30
}
