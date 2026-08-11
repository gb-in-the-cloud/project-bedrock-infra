#Why managed over in-cluster?
#   In-cluster databases lose data when pods restart or nodes are replaced.
#   RDS provides automated backups, point-in-time recovery, and
#   multi-AZ failover. DynamoDB is serverless and infinitely scalable.
#   For a production retail application, this is non-negotiable.
#
# Why single-AZ RDS?
#   Cost guardrail. Multi-AZ doubles the RDS cost. Single-AZ with
#   automated backups is sufficient for this assessment.

# ── Data ─────────────────────────────────────────────────────────────────────
data "aws_vpc" "main" {
  id = var.vpc_id
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# Both RDS instances share one subnet group across private subnets
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# ── Security Group: RDS MySQL ─────────────────────────────────────────────────
# Only allows inbound MySQL traffic from EKS node security group
resource "aws_security_group" "mysql" {
  name        = "${var.project_name}-mysql-sg"
  description = "Allow MySQL from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-mysql-sg" }
}

# ── Security Group: RDS PostgreSQL ────────────────────────────────────────────
resource "aws_security_group" "postgresql" {
  name        = "${var.project_name}-postgresql-sg"
  description = "Allow PostgreSQL from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-postgresql-sg" }
}

# ── RDS MySQL — Catalog Service ───────────────────────────────────────────────
resource "random_password" "mysql" {
  length  = 16
  special = false # Avoid special chars that break connection strings
}

resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t2.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "catalog"
  username = "catalog_user"
  password = random_password.mysql.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.mysql.id]

  # Single-AZ — cost guardrail (assessed requirement)
  multi_az            = false
  publicly_accessible = false

  # Backups not retained because of tier level
  backup_retention_period = 0

  # On destroy — skip final snapshot for dev environment
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${var.project_name}-mysql" }
}

# ── RDS PostgreSQL — Orders Service ──────────────────────────────────────────
resource "random_password" "postgresql" {
  length  = 16
  special = false
}

resource "aws_db_instance" "postgresql" {
  identifier        = "${var.project_name}-postgresql"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = "db.t2.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "orders"
  username = "orders_user"
  password = random_password.postgresql.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  multi_az            = false
  publicly_accessible = false

  backup_retention_period = 0

  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${var.project_name}-postgresql" }
}

# ── DynamoDB — Carts Service ──────────────────────────────────────────────────
# On-demand billing — pay per request, no provisioned capacity needed
resource "aws_dynamodb_table" "carts" {
  name         = "${var.project_name}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "${var.project_name}-carts" }
}

# ── Secrets Manager — MySQL Credentials ──────────────────────────────────────
# Credentials stored in Secrets Manager — never in Helm values or git
resource "aws_secretsmanager_secret" "mysql" {
  name                    = "${var.project_name}/mysql"
  recovery_window_in_days = 0 # Instant deletion for dev

  tags = { Name = "${var.project_name}-mysql-secret" }
}

resource "aws_secretsmanager_secret_version" "mysql" {
  secret_id = aws_secretsmanager_secret.mysql.id

  secret_string = jsonencode({
    username = aws_db_instance.mysql.username
    password = random_password.mysql.result
    host     = aws_db_instance.mysql.address
    port     = aws_db_instance.mysql.port
    dbname   = aws_db_instance.mysql.db_name
    url      = "mysql://${aws_db_instance.mysql.username}:${random_password.mysql.result}@${aws_db_instance.mysql.address}:${aws_db_instance.mysql.port}/${aws_db_instance.mysql.db_name}"
  })
}

# ── Secrets Manager — PostgreSQL Credentials ──────────────────────────────────
resource "aws_secretsmanager_secret" "postgresql" {
  name                    = "${var.project_name}/postgresql"
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-postgresql-secret" }
}

resource "aws_secretsmanager_secret_version" "postgresql" {
  secret_id = aws_secretsmanager_secret.postgresql.id

  secret_string = jsonencode({
    username = aws_db_instance.postgresql.username
    password = random_password.postgresql.result
    host     = aws_db_instance.postgresql.address
    port     = aws_db_instance.postgresql.port
    dbname   = aws_db_instance.postgresql.db_name
    url      = "postgresql://${aws_db_instance.postgresql.username}:${random_password.postgresql.result}@${aws_db_instance.postgresql.address}:${aws_db_instance.postgresql.port}/${aws_db_instance.postgresql.db_name}"
  })
}
