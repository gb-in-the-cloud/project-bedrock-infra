output "assets_bucket_name"    { value = aws_s3_bucket.assets.bucket }
output "assets_bucket_arn"     { value = aws_s3_bucket.assets.arn }
output "lambda_function_name"  { value = aws_lambda_function.asset_processor.function_name }
output "lambda_function_arn"   { value = aws_lambda_function.asset_processor.arn }
output "eventbridge_rule_name" { value = aws_cloudwatch_event_rule.s3_upload.name }
output "eventbridge_rule_arn"  { value = aws_cloudwatch_event_rule.s3_upload.arn }