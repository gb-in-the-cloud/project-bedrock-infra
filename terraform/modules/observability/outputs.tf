output "log_group_name"            { value = aws_cloudwatch_log_group.cluster.name }
output "app_log_group_name"        { value = aws_cloudwatch_log_group.application.name }
output "fluent_bit_role_arn"       { value = aws_iam_role.fluent_bit.arn }
output "cloudwatch_agent_role_arn" { value = aws_iam_role.cloudwatch_agent.arn }