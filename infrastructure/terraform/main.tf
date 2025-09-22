provider "aws" {
  region = var.region
}

locals {
  input_bucket_name  = coalesce(var.input_bucket_name, "${var.project}-input-${var.environment}")
  output_bucket_name = coalesce(var.output_bucket_name, "${var.project}-output-${var.environment}")
  sns_topic_name     = coalesce(var.sns_topic_name, "${var.project}-notifications-${var.environment}")
  lambda_zip_path    = "${path.module}/.terraform/api_lambda.zip"
}

resource "aws_s3_bucket" "input" {
  bucket = local.input_bucket_name

  tags = merge(var.default_tags, {
    "Name"        = "${var.project}-${var.environment}-input"
    "Environment" = var.environment
  })
}

resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket_name

  tags = merge(var.default_tags, {
    "Name"        = "${var.project}-${var.environment}-output"
    "Environment" = var.environment
  })
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/batch/${var.project}/${var.environment}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_iam_role" "batch_service" {
  name               = "${var.project}-${var.environment}-batch-service"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume.json
}

data "aws_iam_policy_document" "batch_service_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

resource "aws_iam_role" "batch_instance" {
  name               = "${var.project}-${var.environment}-batch-instance"
  assume_role_policy = data.aws_iam_policy_document.batch_instance_assume.json
}

data "aws_iam_policy_document" "batch_instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "batch_instance" {
  role       = aws_iam_role.batch_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "batch_instance" {
  name = "${var.project}-${var.environment}-batch-instance"
  role = aws_iam_role.batch_instance.name
}

resource "aws_security_group" "batch_compute" {
  name        = "${var.project}-${var.environment}-batch-sg"
  description = "Security group for Batch compute resources"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.default_tags, {
    "Name" = "${var.project}-${var.environment}-batch-sg"
  })
}

resource "aws_batch_compute_environment" "ollama" {
  compute_environment_name = "${var.project}-${var.environment}-ollama"
  service_role              = aws_iam_role.batch_service.arn
  type                      = "MANAGED"

  compute_resources {
    type                = "SPOT"
    max_vcpus           = var.batch_max_vcpus
    min_vcpus           = var.batch_min_vcpus
    desired_vcpus       = var.batch_desired_vcpus
    instance_types      = var.batch_instance_types
    allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
    subnets             = var.subnet_ids
    instance_role       = aws_iam_instance_profile.batch_instance.arn
    security_group_ids  = [aws_security_group.batch_compute.id]
    bid_percentage      = var.batch_spot_bid_percentage
  }

  tags = merge(var.default_tags, {
    "Name" = "${var.project}-${var.environment}-compute"
  })
}

resource "aws_iam_role" "batch_job" {
  name               = "${var.project}-${var.environment}-batch-job"
  assume_role_policy = data.aws_iam_policy_document.batch_job_assume.json
}

data "aws_iam_policy_document" "batch_job_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "batch_job_policy" {
  statement {
    sid = "S3Access"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*",
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }

  statement {
    sid = "SNSPublish"

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.results.arn]
  }
}

resource "aws_iam_policy" "batch_job" {
  name   = "${var.project}-${var.environment}-batch-job"
  policy = data.aws_iam_policy_document.batch_job_policy.json
}

resource "aws_iam_role_policy_attachment" "batch_job" {
  role       = aws_iam_role.batch_job.name
  policy_arn = aws_iam_policy.batch_job.arn
}

resource "aws_batch_job_queue" "ollama" {
  name                 = "${var.project}-${var.environment}-queue"
  state                = "ENABLED"
  priority             = 1
  compute_environments = [aws_batch_compute_environment.ollama.arn]
}

resource "aws_batch_job_definition" "ollama" {
  name = "${var.project}-${var.environment}-job"
  type = "container"

  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image        = var.batch_job_image
    vcpus        = var.job_vcpus
    memory       = var.job_memory
    command      = ["python3", "-m", "runner"]
    jobRoleArn   = aws_iam_role.batch_job.arn
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "batch"
      }
    }
    environment = [
      {
        name  = "INPUT_BUCKET"
        value = aws_s3_bucket.input.bucket
      },
      {
        name  = "OUTPUT_BUCKET"
        value = aws_s3_bucket.output.bucket
      },
      {
        name  = "SNS_TOPIC_ARN"
        value = aws_sns_topic.results.arn
      },
      {
        name  = "DEFAULT_PROMPT_FILE"
        value = var.default_prompt_file
      },
      {
        name  = "DEFAULT_OUTPUT_FILE"
        value = var.default_output_file
      },
      {
        name  = "OLLAMA_MODEL"
        value = var.ollama_model
      }
    ]
  })
}

resource "aws_sns_topic" "results" {
  name = local.sns_topic_name

  tags = merge(var.default_tags, {
    "Name" = local.sns_topic_name
  })
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_lambda" {
  name               = "${var.project}-${var.environment}-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "api_lambda_policy" {
  statement {
    sid     = "AllowBatch"
    actions = ["batch:SubmitJob"]
    resources = [
      aws_batch_job_definition.ollama.arn,
      aws_batch_job_queue.ollama.arn
    ]
  }

  statement {
    sid     = "AllowLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "api_lambda" {
  name   = "${var.project}-${var.environment}-api"
  policy = data.aws_iam_policy_document.api_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "api_lambda" {
  role       = aws_iam_role.api_lambda.name
  policy_arn = aws_iam_policy.api_lambda.arn
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.project}-${var.environment}-api"
  retention_in_days = var.log_retention_in_days
}

data "archive_file" "api_lambda" {
  type        = "zip"
  output_path = local.lambda_zip_path
  source_dir  = "${path.module}/../../lambda/api"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project}-${var.environment}-submit-job"
  role          = aws_iam_role.api_lambda.arn
  runtime       = "python3.11"
  handler       = "handler.lambda_handler"
  filename      = data.archive_file.api_lambda.output_path
  timeout       = 30

  source_code_hash = data.archive_file.api_lambda.output_base64sha256

  environment {
    variables = {
      JOB_QUEUE_ARN     = aws_batch_job_queue.ollama.arn
      JOB_DEFINITION_ARN = aws_batch_job_definition.ollama.arn
      DEFAULT_VCPU      = tostring(var.job_vcpus)
      DEFAULT_MEMORY    = tostring(var.job_memory)
      DEFAULT_TIMEOUT   = tostring(var.job_timeout_seconds)
      DEFAULT_PROMPT_FILE = var.default_prompt_file
      DEFAULT_OUTPUT_FILE = var.default_output_file
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
}

resource "aws_apigatewayv2_api" "rest" {
  name          = "${var.project}-${var.environment}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.rest.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_submit" {
  api_id    = aws_apigatewayv2_api.rest.id
  route_key = "POST /submit"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.rest.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = jsonencode({
      requestId = "$context.requestId"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
    })
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rest.execution_arn}/*/*"
}

output "input_bucket_name" {
  value = aws_s3_bucket.input.bucket
}

output "output_bucket_name" {
  value = aws_s3_bucket.output.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.results.arn
}

output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}
