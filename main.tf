terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.6.2"
    }
  }
}

resource "aws_instance" "jenkins" {
  ami                         = var.ami_id 
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public1.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  key_name                    = var.key_name   
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}_jenkins"
  }

    user_data = <<EOF
#!/bin/bash
set -e

# Jenkins 디렉토리 준비
mkdir -p /home/ubuntu/jenkins/jenkins_home
chown ubuntu:ubuntu /home/ubuntu/jenkins

# docker-compose.yml 파일 복원
echo "${filebase64("${path.module}/jenkins/docker-compose.yaml")}" | base64 -d > /home/ubuntu/jenkins/docker-compose.yml
echo "${filebase64("${path.module}/jenkins/Dockerfile")}" | base64 -d > /home/ubuntu/jenkins/Dockerfile

# 권한 설정
chown -R ubuntu:ubuntu /home/ubuntu/jenkins
chmod -R 644 /home/ubuntu/jenkins/*

# Docker 설치
apt-get update
apt-get install -y docker.io docker-compose

# Jenkins 빌드 및 실행
cd /home/ubuntu/jenkins
docker-compose up -d
EOF

}

# bastion EC2
resource "aws_instance" "bastion" {
  ami                         = var.ami_id 
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public1.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = var.key_name   
  associate_public_ip_address = true                # 공인 IP 필요하므로 true

  root_block_device {
    volume_size = 8                # 디스크 용량 (GB)
    volume_type = "gp3"            # 최신 SSD (gp3 권장)
    delete_on_termination = true   # 인스턴스 삭제 시 볼륨도 삭제
  }
  user_data = <<EOF
#!/bin/bash
echo "${filebase64("coubee-keypair.pem")}" | base64 -d > /home/ubuntu/private-key.pem
chmod 400 /home/ubuntu/private-key.pem
chown ubuntu:ubuntu /home/ubuntu/private-key.pem
EOF
  

  tags = {
    Name = "${var.project_name}_bastion"
  }
}

# kafka EC2
resource "aws_instance" "kafka" {
  ami                         = var.ami_id
  instance_type               = var.kafka_instance_type
  subnet_id                   = aws_subnet.private1.id
  vpc_security_group_ids      = [aws_security_group.kafka_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  root_block_device {
    volume_size = 20                # 디스크 용량 (GB)
    volume_type = "gp3"            # 최신 SSD (gp3 권장)
    delete_on_termination = true   # 인스턴스 삭제 시 볼륨도 삭제
  }


  user_data = file("install-kafka.sh")

  depends_on = [                                 #네트워크 설정이 먼저 되어있어야 private망에 있는 ec2접근이 가능해져서 kafka 설치됨
    aws_nat_gateway.nat_a,
    aws_route_table_association.private1_assoc
  ]

  tags = {
    Name = "${var.project_name}_kafka"
  }
}

# python EC2
resource "aws_instance" "python_ec2" {
  ami                         = var.ami_id
  instance_type               = var.python_instance_type
  subnet_id                   = aws_subnet.private2.id
  vpc_security_group_ids      = [aws_security_group.python-ec2-sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  tags = {
    Name = "${var.project_name}_python"
  }
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-notification-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda가 VPC ENI를 붙일 수 있도록
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_personalize" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# custom role
resource "aws_iam_role_policy" "lambda_notification_policy" {
  name = "${var.project_name}-notification-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:*:*:function:${var.project_name}-notification-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.dlq_alerts.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/${var.project_name}/notification/*"
        ]
      }
    ]
  })
}

# 1) elsaticache endpoint Parameter 생성/갱신
resource "aws_ssm_parameter" "valkey_endpoint" {
  name  = "/${var.project_name}/notification/valkey/endpoint"
  type  = "String"
  value = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

resource "aws_ssm_parameter" "expo_access_token" {
  name = "/${var.project_name}/notification/expo/access_token"
  type = "SecureString"
  value = var.expo_access_token
}

# SNS Topic for DLQ Alerts
resource "aws_sns_topic" "dlq_alerts" {
  name = "${var.project_name}-notification-dlq-alerts"
}

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

# 2) Lambda가 SSM 읽도록 IAM 권한 부여
resource "aws_iam_role_policy_attachment" "lambda_ssm_read" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
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

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "dispatcher_logs" {
  name              = "/aws/lambda/${var.project_name}-notification-dispatcher"
  retention_in_days = 14

  tags = {
    Name = "dispatcher-log"
  }
}

resource "aws_cloudwatch_log_group" "worker_logs" {
  name              = "/aws/lambda/${var.project_name}-notification-worker"
  retention_in_days = 14

  tags = {
    Name = "worker-log"
  }
}


# Archive Python code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# EventBridge Custom Event Bus
resource "aws_cloudwatch_event_bus" "notification_bus" {
  name = "notification_bus"
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "order_status_rule" {
  name           = "notification_send_rule"
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name

  event_pattern = jsonencode({
    "source"      = ["coubee.notification"]
    "detail-type" = ["notification_send"]
  })
}

# EventBridge Target: Dispatcher Lambda
resource "aws_cloudwatch_event_target" "dispatcher_target" {
  rule           = aws_cloudwatch_event_rule.order_status_rule.name
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name
  target_id      = "DispatcherLambda"
  arn            = aws_lambda_function.dispatcher.arn
}



# Permission for EventBridge to invoke Dispatcher Lambda
resource "aws_lambda_permission" "allow_eventbridge_dispatcher" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_status_rule.arn
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "notification_dashboard" {
  dashboard_name = "${var.project_name}-notification-system"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["NotificationSystem/Dispatcher", "DispatcherSuccess"],
            [".", "DispatcherError"],
            ["NotificationSystem", "ImmediateSend"],
            [".", "QueuedNotifications"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "ap-northeast-2"
          title   = "Notification System Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${var.project_name}-notification-dispatcher' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = "ap-northeast-2"
          title   = "Dispatcher Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "dispatcher_errors" {
  alarm_name          = "${var.project_name}-notification-dispatcher-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors dispatcher lambda errors"
  alarm_actions       = [aws_sns_topic.dlq_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.dispatcher.function_name
  }

  tags = {
    Name = "dispatcher_errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_errors" {
  alarm_name          = "${var.project_name}-notification-worker-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors worker lambda errors"
  alarm_actions       = [aws_sns_topic.dlq_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  tags = {
    Name = "worker_errors"
  }
}


# personalize lambda
#lambda용 role
resource "aws_iam_role" "lambda_personalize_exec" {
  name = "lambda-personalize-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "lambda_psersonalize_role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_personalize_access" {
  role       = aws_iam_role.lambda_personalize_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_personalize_vpc" {
  role       = aws_iam_role.lambda_personalize_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_personalize_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# S3 import logging
resource "aws_iam_role_policy" "lambda_s3_import_logging" {
  name = "S3ImportLoggingPolicy"
  role = aws_iam_role.lambda_personalize_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:ap-northeast-2:370519913328:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:ap-northeast-2:370519913328:log-group:personalize/s3-import:*"
        ]
      }
    ]
  })
}

#dataset-import-logging
resource "aws_iam_role_policy" "dataset_import_logging" {
  name = "dataset_import_logging"
  role = aws_iam_role.lambda_personalize_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:ap-northeast-2:370519913328:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:ap-northeast-2:370519913328:log-group:/aws/lambda/dataset_import:*"
        ]
      }
    ]
  })
}

#solution_import로깅 role 추가
resource "aws_iam_role_policy" "solution_import_logging" {
  name = "solutionimportlogging"
  role = aws_iam_role.lambda_personalize_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:ap-northeast-2:370519913328:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:ap-northeast-2:370519913328:log-group:/aws/lambda/solution_import:*"
        ]
      }
    ]
  })
}

#solution_import로깅 role 추가
resource "aws_iam_role_policy" "batch_inference_import_logging" {
  name = "solutionimportlogging"
  role = aws_iam_role.lambda_personalize_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:ap-northeast-2:370519913328:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:ap-northeast-2:370519913328:log-group:/aws/lambda/batch_inference_import_import:*"
        ]
      }
    ]
  })
}

#personalize role
resource "aws_iam_role" "personalize_exec" {
  name = "PersonalizeExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "personalize.amazonaws.com"
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
  tags = {
    Name = "PersonalizeExecutionRole"
  }
}

resource "aws_iam_role_policy_attachment" "personalize_full_access" {
  role       = aws_iam_role.personalize_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}

resource "aws_iam_role_policy" "personalize_s3_access" {
  name = "PersonalizeS3BucketAccessPolicy"
  role = aws_iam_role.personalize_exec.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:ListBucket"],
        Effect   = "Allow",
        Resource = ["arn:aws:s3:::${var.bucket_name}"]
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = ["arn:aws:s3:::${var.bucket_name}/*"]
      }
    ]
  })
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

resource "aws_cloudwatch_log_group" "s3_log_group" {
  name              = "/aws/lambda/s3_import"
  retention_in_days = 14
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

resource "aws_cloudwatch_log_group" "dataset_log_group" {
  name              = "/personalize/dataset_import"
  retention_in_days = 14
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

resource "aws_cloudwatch_log_group" "solution_log_group" {
  name              = "/aws/lambda/solution_import"
  retention_in_days = 14
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

resource "aws_cloudwatch_log_group" "batch_inference_import_log_group" {
  name              = "/aws/lambda/batch_inference_import"
  retention_in_days = 14
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
      DB_NAME = var.db_name
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

resource "aws_cloudwatch_log_group" "load_server_clean_log_group" {
  name              = "/aws/lambda/load_server_cleant"
  retention_in_days = 14
}

# EKS IAM Role (Cluster)
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}_eks_cluster_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster Role에 추가로 붙일 관리형 정책들
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSBlockStoragePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSComputePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSLoadBalancingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSNetworkingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# # EKS Cluster
# resource "aws_eks_cluster" "eks_cluster" {
#   name     = "${var.project_name}_eks_cluster"
#   role_arn = aws_iam_role.eks_cluster_role.arn
#   version  = "1.33"

#   vpc_config {
#     subnet_ids         = [aws_subnet.private1.id, aws_subnet.private2.id] 
#     security_group_ids = [aws_security_group.eks_cluster_sg.id]
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSBlockStoragePolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSComputePolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSLoadBalancingPolicy,
#     aws_iam_role_policy_attachment.eks_cluster_AmazonEKSNetworkingPolicy
#   ]
# }

# (선택) 현재 리전/계정 정보
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# EKS Node Role에 Inline Policy 추가 (EventBridge PutEvents)
resource "aws_iam_role_policy" "eks_node_put_events_inline" {
  name = "eks-node-put-events-inline"
  role = aws_iam_role.eks_node_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "events:PutEvents",
        Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/notification_bus"
      }
    ]
  })
}

# EKS IAM Role (Node Group)
resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}_eks_node_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}


# 최소 권한 노드 정책 (기존 AmazonEKSWorkerNodePolicy → 대체)
resource "aws_iam_role_policy_attachment" "eks_worker_node_minimal_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.eks_node_role.name
}

# CNI 정책은 유지
resource "aws_iam_role_policy_attachment" "eks_worker_node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

# ECR Pull 전용 (기존 ReadOnly → 대체)
resource "aws_iam_role_policy_attachment" "eks_worker_node_ecr_pull_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.eks_node_role.name
}

# # Launch Template for Node Group
# resource "aws_launch_template" "eks_node_lt" {
#   name_prefix   = "${var.project_name}_eks_node_"
#   instance_type = "t3a.medium"
#   key_name = var.key_name

#   block_device_mappings {
#     device_name = "/dev/xvda"
#     ebs {
#       volume_size           = 20
#       volume_type           = "gp3"
#       delete_on_termination = true
#     }
#   }

#   vpc_security_group_ids = [aws_security_group.eks_node_sg.id]

#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${var.project_name}_eks_node"
#     }
#   }
# }

# # Node Group
# resource "aws_eks_node_group" "eks_node_group" {
#   cluster_name    = aws_eks_cluster.eks_cluster.name
#   node_group_name = "${var.project_name}_eks_node_group"
#   node_role_arn   = aws_iam_role.eks_node_role.arn
#   subnet_ids      = [aws_subnet.private1.id]



#   scaling_config {
#     desired_size = 6
#     max_size     = 6
#     min_size     = 6
#   }

#   launch_template {
#     id      = aws_launch_template.eks_node_lt.id
#     version = "$Latest"
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_worker_node_minimal_policy,
#     aws_iam_role_policy_attachment.eks_worker_node_cni_policy,
#     aws_iam_role_policy_attachment.eks_worker_node_ecr_pull_only
#   ]
# }

resource "aws_ecr_repository" "gateway" {
  name = "coubee-be-gateway"
  force_delete = true
}

resource "aws_ecr_repository" "user" {
  name = "coubee-be-user"
  force_delete = true
}

resource "aws_ecr_repository" "product" {
  name = "coubee-be-product"
  force_delete = true
}

resource "aws_ecr_repository" "store" {
  name = "coubee-be-store"
  force_delete = true
}

resource "aws_ecr_repository" "notification" {
  name = "coubee-be-notification"
  force_delete = true
}

resource "aws_ecr_repository" "order" {
  name = "coubee-be-order"
  force_delete = true
}

resource "aws_ecr_repository" "elasticsearch" {
  name = "coubee-infra-elasticsearch"
  force_delete = true
}

resource "aws_ecr_repository" "logstash" {
  name = "coubee-infra-logstash"
  force_delete = true
}

resource "aws_ecr_repository" "kibana" {
  name = "coubee-infra-kibana"
  force_delete = true
}
########################################
# Subnet Group (private2)
########################################
resource "aws_elasticache_subnet_group" "valkey_sng" {
  name       = "valkey-private2-sng"
  subnet_ids = [aws_subnet.private2.id]

  tags = { Name = "valkey-private2-sng" }
}

########################################
# Valkey 8.1 (단일 노드, replica 0, Multi-AZ 해제)
########################################
resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "coubee-valkey-rg"
  description          = "Valkey cache for coubee"

  engine               = "valkey"
  engine_version       = "8.1"
  node_type            = "cache.t3.micro"
  port                 = 6379
  parameter_group_name = "default.valkey8"

  # 클러스터 모드 해제 + 단일 프라이머리
  num_node_groups         = 1
  replicas_per_node_group = 0

  # 멀티 AZ 비활성 (replica가 없으니 자동 장애조치도 비활성/생략)
  multi_az_enabled = false
  # automatic_failover_enabled = false  # 없어도 됨(복제본 없으면 의미 없음)

  # 네트워킹
  subnet_group_name  = aws_elasticache_subnet_group.valkey_sng.name
  security_group_ids = [aws_security_group.lambda-valkey-sg.id]

  # 암호화 (요청: 전송암호화 사용X/보류)
  transit_encryption_enabled = false
  at_rest_encryption_enabled = false

  tags = { Name = "coubee-valkey" }
}


#RDS
resource "aws_db_subnet_group" "rds" {
  name        = "coubee-rds-subnet"
  description = "Subnet group for RDS"
  subnet_ids  = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]
}

resource "aws_db_instance" "postgres" {
  identifier = "coubee-postgres"
  engine = "postgres"
  instance_class = var.db_instance_type

  allocated_storage = 20
  storage_type = "gp3"

  db_subnet_group_name = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible = false
  availability_zone = "ap-northeast-2b"
  port = 5432

  username = var.db_username
  password = var.db_password

  multi_az = false

  #운영 편의 설정
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately = true

  tags = {
    Name = "coubee-postgres"
    Project = "coubee"
  }
}


#ELK EC2
resource "aws_instance" "elk_ec2"{
  ami = var.ami_id
  instance_type = var.elk_instance_type
  subnet_id = aws_subnet.private2.id
  vpc_security_group_ids = [aws_security_group.elk_sg.id]
  key_name = var.key_name

  root_block_device {
    volume_size = 30                # 디스크 용량 (GB)
    volume_type = "gp3"            # 최신 SSD (gp3 권장)
    delete_on_termination = true   # 인스턴스 삭제 시 볼륨도 삭제
  }

  #EC2 초기설정 (cloud-init)
  user_data = <<EOF
#!/bin/bash
set -euxo pipefail
apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
usermod -aG docker ubuntu

# docker compose v2 설치 (경로 먼저 생성!)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -L "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
EOF


  tags = {
    Name = "${var.project_name}_elk"
  }
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


#step_function용 role
resource "aws_iam_role" "step_function_exec" {
  name = "step_function_role"
  # Principal(서비스 주체)을 Step Functions로 변경해야 합니다.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
  tags = {
    Name = "step_function_role"
  }
}
resource "aws_iam_role_policy_attachment" "step_function_personalize_access" {
  role       = aws_iam_role.step_function_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}
resource "aws_iam_policy" "step_function_logs_policy" {
  name        = "StepFunctionLogsPolicy"
  description = "Allows Step Functions to manage CloudWatch log deliveries."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ],
        Resource = "*"
      }
    ]
  })
}
# 2-2. Lambda 함수 호출 정책
resource "aws_iam_policy" "step_function_lambda_invoke_policy" {
  name        = "StepFunctionLambdaInvokePolicy"
  description = "Allows Step Functions to invoke specific Lambda functions."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "lambda:InvokeFunction",
        Resource = [
          "arn:aws:lambda:ap-northeast-2:${var.iam_id}:function:s3_import",
          "arn:aws:lambda:ap-northeast-2:${var.iam_id}:function:dataset_import",
          "arn:aws:lambda:ap-northeast-2:${var.iam_id}:function:solution_import",
          "arn:aws:lambda:ap-northeast-2:${var.iam_id}:function:batch_inference_import",
          "arn:aws:lambda:ap-northeast-2:${var.iam_id}:function:load_server_clean_import"
        ]
      }
    ]
  })
}
# 2-3. AWS X-Ray 접근 정책
resource "aws_iam_policy" "step_function_xray_policy" {
  name        = "StepFunctionXRayPolicy"
  description = "Allows Step Functions to send trace data to X-Ray."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ],
        Resource = ["*"]
      }
    ]
  })
}
# 3. 위에서 생성한 정책들을 Step Function 역할에 연결(attach)합니다.
resource "aws_iam_role_policy_attachment" "sf_logs_attach" {
  role       = aws_iam_role.step_function_exec.name
  policy_arn = aws_iam_policy.step_function_logs_policy.arn
}
resource "aws_iam_role_policy_attachment" "sf_lambda_invoke_attach" {
  role       = aws_iam_role.step_function_exec.name
  policy_arn = aws_iam_policy.step_function_lambda_invoke_policy.arn
}
resource "aws_iam_role_policy_attachment" "sf_xray_attach" {
  role       = aws_iam_role.step_function_exec.name
  policy_arn = aws_iam_policy.step_function_xray_policy.arn
}
resource "aws_sfn_state_machine" "personalize_pipeline" {
  name     = "PersonalizePipelineStateMachine" # 상태 머신의 이름
  role_arn = aws_iam_role.step_function_exec.arn
  # file() 함수를 사용해 외부 JSON 파일의 내용을 읽어와서 정의로 사용합니다.
  definition = file("${path.module}/personalize_pipeline.json")
  # 로깅 설정 (선택 사항이지만 디버깅에 매우 유용하므로 강력히 권장합니다.)
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}
# Step Function 실행 로그를 저장할 CloudWatch Log Group
resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name              = "/aws/vendedlogs/states/PersonalizePipelineLogs"
  retention_in_days = 14 # 로그 보존 기간 (일)
}