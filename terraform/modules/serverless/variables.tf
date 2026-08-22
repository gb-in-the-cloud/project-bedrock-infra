variable "project_name" { type = string }
variable "project_tag" { type = string }
variable "environment" { type = string }
variable "student_id" { type = string }
variable "cluster_name" { type = string }
variable "dev_view_user_arn" {
  type        = string
  description = "ARN of bedrock-dev-view IAM user — granted s3:PutObject for grader testing"
}