# project-bedrock-infra
Production grade Infrastructure for project bedrock

The following resources must be created manually and are NOT destroyed
by `terraform destroy`:

- S3 State Bucket: `project-bedrock-tfstate-alt-soe-tin-025-0007`

To fully clean up after the project:
1. Run `terraform destroy`
2. Manually empty and delete the state bucket:
   aws s3 rm s3://project-bedrock-tfstate-alt-soe-tin-025-0007 --recursive
   aws s3api delete-bucket --bucket project-bedrock-tfstate-alt-soe-tin-***-****