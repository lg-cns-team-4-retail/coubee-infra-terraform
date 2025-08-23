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

# 2) Lambda가 SSM 읽도록 IAM 권한 부여
resource "aws_iam_role_policy_attachment" "lambda_ssm_read" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
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