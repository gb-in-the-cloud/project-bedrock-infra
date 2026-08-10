# Serverless Module
# Creates:
#   - S3 bucket:    bedrock-assets-[student-id]     (assessed naming)
#   - Lambda:       bedrock-asset-processor          (assessed naming)
#   - EventBridge:  triggers Lambda on S3 PutObject events
#   - IAM role:     least-privilege Lambda execution role
#   - CloudWatch:   log group for Lambda output

# Architecture:
#   S3 PutObject event → EventBridge → Lambda → CloudWatch Logs
# ── S3 Assets Bucket ──────────────────────────────────────────────────────────
# Naming: bedrock-assets-[student-id] (assessed requirement)
resource "aws_s3_bucket" "assets" {
  bucket = "bedrock-assets-${var.student_id}"

  # force_destroy allows terraform destroy to delete the bucket even
  # if it contains objects — required for clean teardown
  force_destroy = true

  tags = { Name = "bedrock-assets-${var.student_id}" }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable EventBridge notifications from S3
resource "aws_s3_bucket_notification" "assets" {
  bucket      = aws_s3_bucket.assets.id
  eventbridge = true
}

# ── IAM: Lambda Execution Role ────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-lambda-role" }
}

# Least privilege: Lambda only needs basic execution (write CloudWatch logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow Lambda to read the S3 bucket it processes
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:HeadObject"]
      Resource = "${aws_s3_bucket.assets.arn}/*"
    }]
  })
}

# ── Lambda Function Code ──────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "/tmp/bedrock-asset-processor.zip"

  source {
    filename = "index.js"
    content  = <<-JS
      /**
       * bedrock-asset-processor
       *
       * Triggered by EventBridge when an object is uploaded to the
       * bedrock-assets S3 bucket. Logs structured metadata about the
       * upload event to CloudWatch.
       *
       * Real-world extensions:
       *   - Trigger image resizing via AWS Batch
       *   - Publish to SNS for downstream consumers
       *   - Index metadata into DynamoDB
       *   - Trigger a Kubernetes Job via EKS API
       */
      exports.handler = async (event) => {
        const detail = event.detail || {};

        const record = {
          timestamp:    new Date().toISOString(),
          eventSource:  event.source,
          eventType:    event['detail-type'],
          bucketName:   detail.bucket?.name,
          objectKey:    detail.object?.key,
          objectSize:   detail.object?.size,
          region:       event.region,
          projectName:  process.env.PROJECT_NAME,
          clusterName:  process.env.CLUSTER_NAME,
        };

        console.log(JSON.stringify({
          level:   'INFO',
          message: 'Asset upload processed',
          ...record,
        }));

        return {
          statusCode: 200,
          body: JSON.stringify({ message: 'Asset processed', key: record.objectKey }),
        };
      };
    JS
  }
}

# ── Lambda Function ───────────────────────────────────────────────────────────
# Naming: bedrock-asset-processor (assessed requirement)
resource "aws_lambda_function" "asset_processor" {
  function_name    = "bedrock-asset-processor"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 30
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      CLUSTER_NAME = var.cluster_name
      BUCKET_NAME  = aws_s3_bucket.assets.bucket
    }
  }

  tags = { Name = "bedrock-asset-processor" }
}

# ── CloudWatch Log Group: Lambda ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.asset_processor.function_name}"
  retention_in_days = 14
  tags              = { Name = "${var.project_name}-lambda-logs" }
}

# ── EventBridge Rule ──────────────────────────────────────────────────────────
# Listens for S3 object creation events from the assets bucket
resource "aws_cloudwatch_event_rule" "s3_upload" {
  name        = "${var.project_name}-s3-upload"
  description = "Trigger bedrock-asset-processor on S3 object uploads"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.assets.bucket]
      }
    }
  })

  tags = { Name = "${var.project_name}-s3-upload-rule" }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "AssetProcessor"
  arn       = aws_lambda_function.asset_processor.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asset_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_upload.arn
}