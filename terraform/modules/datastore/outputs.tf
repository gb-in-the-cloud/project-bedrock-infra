output "mysql_host" { value = aws_db_instance.mysql.address }
output "mysql_port" { value = aws_db_instance.mysql.port }
output "mysql_db_name" { value = aws_db_instance.mysql.db_name }
output "mysql_secret_arn" { value = aws_secretsmanager_secret.mysql.arn }

output "postgresql_host" { value = aws_db_instance.postgresql.address }
output "postgresql_port" { value = aws_db_instance.postgresql.port }
output "postgresql_db_name" { value = aws_db_instance.postgresql.db_name }
output "postgresql_secret_arn" { value = aws_secretsmanager_secret.postgresql.arn }

output "dynamodb_carts_table" { value = aws_dynamodb_table.carts.name }
output "dynamodb_carts_arn" { value = aws_dynamodb_table.carts.arn }