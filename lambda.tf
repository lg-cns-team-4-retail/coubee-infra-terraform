# Lambda Layer and package data sources
data "local_file" "dependencies_layer_zip" {
  filename = "${path.module}/lambda/notification-lambda/dependencies-layer.zip"
}

data "local_file" "dispatcher_slim_zip" {
  filename = "${path.module}/lambda/notification-lambda/notification-dispatcher-slim.zip"
}

data "local_file" "worker_slim_zip" {
  filename = "${path.module}/lambda/notification-lambda/notification-worker-slim.zip"
}

# Lambda Layer for shared dependencies
resource "aws_lambda_layer_version" "dependencies" {
  layer_name          = "${var.project_name}-notification-dependencies"
  description         = "Shared dependencies for notification system"
  
  filename            = data.local_file.dependencies_layer_zip.filename
  source_code_hash    = data.local_file.dependencies_layer_zip.content_base64sha256
  
  compatible_runtimes = ["python3.12"]
  
  lifecycle {
    create_before_destroy = true
  }
  
}

# Dispatcher Lambda Function (Layer-based)
resource "aws_lambda_function" "dispatcher" {
  function_name = "${var.project_name}-notification-dispatcher"
  role          = aws_iam_role.lambda_exec.arn
  
  runtime = "python3.12"
  handler = "dispatcher.lambda_handler"
  timeout = var.lambda_timeout_dispatcher
  memory_size = var.lambda_memory_dispatcher
  
  filename         = data.local_file.dispatcher_slim_zip.filename
  source_code_hash = data.local_file.dispatcher_slim_zip.content_base64sha256

  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.dependencies.arn]

  # vpc 연결 (private1)
  vpc_config {
    subnet_ids         = [aws_subnet.private1.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      VALKEY_HOST             = aws_ssm_parameter.valkey_endpoint.value
      VALKEY_PORT             = "6379"
      WORKER_FUNCTION_NAME    = "${var.project_name}-notification-worker"
      ERROR_ALERT_TOPIC_ARN   = aws_sns_topic.dlq_alerts.arn
      EXPO_ACCESS_TOKEN       = var.expo_access_token
      DB_HOST = aws_db_instance.postgres.endpoint
      DB_NAME = var.db_name2
      DB_PASSWORD = var.db_password
      DB_USER = var.db_user
      RDS_ENABLED=true
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.dispatcher_logs,
    aws_lambda_layer_version.dependencies
  ]

  tags = {
    Name = "lambda-dispatcher"
  }
}

# Worker Lambda Function (Layer-based)
resource "aws_lambda_function" "worker" {
  function_name = "${var.project_name}-notification-worker"
  role          = aws_iam_role.lambda_exec.arn
  
  runtime = "python3.12"
  handler = "worker.lambda_handler"
  timeout = var.lambda_timeout_worker
  memory_size = var.lambda_memory_worker
  
  filename         = data.local_file.worker_slim_zip.filename
  source_code_hash = data.local_file.worker_slim_zip.content_base64sha256

  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.dependencies.arn]

  vpc_config {
    subnet_ids         = [aws_subnet.private1.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      VALKEY_HOST             = aws_elasticache_replication_group.valkey.primary_endpoint_address
      VALKEY_PORT             = "6379"
      ERROR_ALERT_TOPIC_ARN   = aws_sns_topic.dlq_alerts.arn
      EXPO_ACCESS_TOKEN       = var.expo_access_token
      DB_HOST = aws_db_instance.postgres.endpoint
      DB_NAME = var.db_name2
      DB_PASSWORD = var.db_password
      DB_USER = var.db_user
      RDS_ENABLED=true
    }
  }

  reserved_concurrent_executions = 5

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.worker_logs,
    aws_lambda_layer_version.dependencies
  ]

  tags = {
    Name = "lambda_worker"
  }
}

# Archive Python code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_layer_version" "python_module" {
    layer_name = "python-module"
    s3_bucket = var.bucket_name
    s3_key = "python.zip"
    compatible_runtimes = ["python3.11"]
}

# 람다 함수 s3_import
data "local_file" "s3_import_zip" {
  filename = "${path.module}/lambda/personalize-lambda/s3_import.zip"
}

resource "aws_lambda_function" "s3_import" {
  function_name = "s3_import"
  role          = aws_iam_role.lambda_personalize_exec.arn
  runtime = "python3.11"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout_personalize
  memory_size = var.lambda_memory_personalize
  filename = data.local_file.s3_import_zip.filename
  source_code_hash = data.local_file.s3_import_zip.content_base64sha256
  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.python_module.arn]
  environment {
    variables = {
        BUCKET_NAME = var.bucket_name
        DB_HOST = aws_db_instance.postgres.endpoint
        DB_PASSWORD = var.db_password
        DB_USER = var.db_user
        INTERACTION_URL = "interaction"
        USER_URL= "user"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private1.id,
                            aws_subnet.private2.id]
    security_group_ids = [aws_security_group.rds_sg.id]
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.s3_log_group,
    aws_lambda_layer_version.python_module
  ]
}

# 람다 함수 dataset_import
data "local_file" "dataset_import_zip" {
  filename = "${path.module}/lambda/personalize-lambda/dataset_import.zip"
}

resource "aws_lambda_function" "dataset-import" {
  function_name = "dataset_import"
  role          = aws_iam_role.lambda_personalize_exec.arn
  runtime = "python3.11"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout_personalize
  memory_size = var.lambda_memory_personalize
  filename = data.local_file.dataset_import_zip.filename
  source_code_hash = data.local_file.dataset_import_zip.content_base64sha256
  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.python_module.arn]
  environment {
    variables = {
      ROLE_ARN = aws_iam_role.personalize_exec.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.dataset_log_group,
    aws_lambda_layer_version.python_module
  ]
}

#solution 람다함수
data "local_file" "solution_import_zip" {
  filename = "${path.module}/lambda/personalize-lambda/solution_import.zip"
}

# solution_import
resource "aws_lambda_function" "solution_import" {
  function_name = "solution_import"
  role          = aws_iam_role.lambda_personalize_exec.arn
  runtime = "python3.11"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout_personalize
  memory_size = var.lambda_memory_personalize
  filename = data.local_file.solution_import_zip.filename
  source_code_hash = data.local_file.solution_import_zip.content_base64sha256
  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.python_module.arn]

  depends_on = [
    aws_cloudwatch_log_group.solution_log_group,
    aws_lambda_layer_version.python_module
  ]
}

#batch_inference_import 람다함수
data "local_file" "batch_inference_import_zip" {
  filename = "${path.module}/lambda/personalize-lambda/batch_inference_import.zip"
}

# batch_inference_import
resource "aws_lambda_function" "batch_inference_import" {
  function_name = "batch_inference_import"
  role          = aws_iam_role.lambda_personalize_exec.arn
  runtime = "python3.11"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout_personalize
  memory_size = var.lambda_memory_personalize
  filename = data.local_file.batch_inference_import_zip.filename
  source_code_hash = data.local_file.batch_inference_import_zip.content_base64sha256
  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.python_module.arn]
  environment {
    variables = {
        BUCKET_NAME = var.bucket_name
        DB_HOST = aws_db_instance.postgres.endpoint
        DB_NAME = "coubee_user"
        DB_PASSWORD = var.db_password
        DB_USER = var.db_user
        OUT_JSON_S3 = "batch_result"
        ROLE_ARN = aws_iam_role.personalize_exec.arn
        USER_JSON_S3 = "user_input"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private1.id,
                            aws_subnet.private2.id]
    security_group_ids = [aws_security_group.rds_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.batch_inference_import_log_group,
    aws_lambda_layer_version.python_module
  ]
}

#load_server_clean 람다함수
data "local_file" "load_server_clean_zip" {
  filename = "${path.module}/lambda/personalize-lambda/load_server_clean_import.zip"
}

# load_server_clean
resource "aws_lambda_function" "load_server_clean" {
  function_name = "load_server_clean_import"
  role          = aws_iam_role.lambda_personalize_exec.arn
  runtime = "python3.11"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout_personalize
  memory_size = var.lambda_memory_personalize
  filename = data.local_file.load_server_clean_zip.filename
  source_code_hash = data.local_file.load_server_clean_zip.content_base64sha256
  # Lambda Layer 연결
  layers = [aws_lambda_layer_version.python_module.arn]
  environment {
    variables = {
      FILE_NAME =   "batch_result"
      SCHEMA_NAME = "coubee_product"
      BUCKET_NAME = var.bucket_name
      DB_HOST = aws_db_instance.postgres.endpoint
      DB_NAME = "coubee_product"
      DB_PASSWORD = var.db_password
      DB_USER = var.db_user
    }
  }

    vpc_config {
    subnet_ids         = [aws_subnet.private1.id,
                            aws_subnet.private2.id]
    security_group_ids = [aws_security_group.rds_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_cloudwatch_log_group.load_server_clean_log_group,
    aws_lambda_layer_version.python_module
  ]
}

# Permission for EventBridge to invoke Dispatcher Lambda
resource "aws_lambda_permission" "allow_eventbridge_dispatcher" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_status_rule.arn
}

# Lambda 함수에 RDS 접근 권한 추가
resource "aws_iam_role_policy" "lambda_rds_policy" {
  count = var.enable_rds_logging ? 1 : 0
  
  name = "${var.project_name}-notification-lambda-rds-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:*:*:dbuser:${var.rds_instance_identifier}/${var.rds_username}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/${var.project_name}/notification/rds/*"
        ]
      }
    ]
  })
}