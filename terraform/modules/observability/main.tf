# Observability Module
# Creates:
#   - CloudWatch log groups (cluster, application, Fluent Bit)
#   - IAM role for Fluent Bit (IRSA — no credentials in pods)
#   - IAM role for CloudWatch Agent (Container Insights)
#   - CloudWatch alarm for high node CPU
# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project_name}-cluster-logs" }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project_name}-app-logs" }
}

resource "aws_cloudwatch_log_group" "fluent_bit" {
  name              = "/aws/eks/${var.cluster_name}/fluent-bit"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project_name}-fluent-bit-logs" }
}

# ── IRSA Role: Fluent Bit ─────────────────────────────────────────────────────
data "aws_iam_policy_document" "fluent_bit_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:amazon-cloudwatch:fluent-bit"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluent_bit" {
  name               = "${var.project_name}-fluent-bit-role"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume.json
  tags               = { Name = "${var.project_name}-fluent-bit-role" }
}

resource "aws_iam_role_policy" "fluent_bit" {
  name = "${var.project_name}-fluent-bit-policy"
  role = aws_iam_role.fluent_bit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
      ]
      Resource = "*"
    }]
  })
}

# ── IRSA Role: CloudWatch Agent (Container Insights) ─────────────────────────
data "aws_iam_policy_document" "cw_agent_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.project_name}-cloudwatch-agent-role"
  assume_role_policy = data.aws_iam_policy_document.cw_agent_assume.json
  tags               = { Name = "${var.project_name}-cloudwatch-agent-role" }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ── CloudWatch Alarm: High CPU ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${var.project_name}-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Node CPU above 80% for 10 minutes on ${var.cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = { ClusterName = var.cluster_name }

  tags = { Name = "${var.project_name}-cpu-alarm" }
}
