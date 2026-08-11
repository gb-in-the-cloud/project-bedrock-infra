# project-bedrock-infra
Production grade Infrastructure for project bedrock

# BEFORE running terraform destroy — backup the state
aws s3 cp \
  s3://project-bedrock-tfstate-alt-soe-tin-***-****/bedrock/terraform.tfstate \
  ./terraform.tfstate.backup

The following resources must be created manually and are NOT destroyed
by `terraform destroy`:

- S3 State Bucket: `project-bedrock-tfstate-alt-soe-tin-025-0007`

To fully clean up after the project:
1. Run `terraform destroy`
2. Manually empty and delete the state bucket:
   aws s3 rm s3://project-bedrock-tfstate-alt-soe-tin-***-**** --recursive
   aws s3api delete-bucket --bucket project-bedrock-tfstate-alt-soe-tin-***-****

## RDS Backup Posture

Free tier accounts restrict backup_retention_period to 0.
For production deployments with a paid account, set:
backup_retention_period = 7  # 7-day retention window
The assessment bonus requires BackupRetentionPeriod > 0 for the resilience objective. This conflicts with the free tier limitation.