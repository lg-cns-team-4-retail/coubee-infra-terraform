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
    volume_size           = 10
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
    aws_nat_gateway.nat,
    aws_route_table_association.private1_assoc
  ]

  tags = {
    Name = "${var.project_name}_kafka"
  }
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_execution_role"

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

# Lambda Function
resource "aws_lambda_function" "notification_lambda" {
  function_name = "handleNotificationEvent"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
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
resource "aws_cloudwatch_event_rule" "notification_send_rule" {
  name           = "notification_send_rule"
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name

  event_pattern = jsonencode({
    "source"      = ["coubee.notification"]
    "detail-type" = ["notification_send"]
  })
}

# EventBridge Target: Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.notification_send_rule.name
  event_bus_name = aws_cloudwatch_event_bus.notification_bus.name
  target_id = "lambda"
  arn       = aws_lambda_function.notification_lambda.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.notification_send_rule.arn
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

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.project_name}_eks_cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.33"

  vpc_config {
    subnet_ids         = [aws_subnet.private1.id, aws_subnet.private3.id] 
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
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


resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_registry_readonly_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Launch Template for Node Group
resource "aws_launch_template" "eks_node_lt" {
  name_prefix   = "${var.project_name}_eks_node_"
  instance_type = "t3a.medium"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [aws_security_group.eks_node_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}_eks_node"
    }
  }
}

# Node Group
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.project_name}_eks_node_group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.private1.id]

  scaling_config {
    desired_size = 6
    max_size     = 6
    min_size     = 6
  }

  launch_template {
    id      = aws_launch_template.eks_node_lt.id
    version = "$Latest"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_worker_node_cni_policy,
    aws_iam_role_policy_attachment.eks_worker_node_registry_readonly_policy
  ]
}

resource "aws_ecr_repository" "gateway" {
  name = "coubee-be-gateway"
}

resource "aws_ecr_repository" "user" {
  name = "coubee-be-user"
}

resource "aws_ecr_repository" "product" {
  name = "coubee-be-product"
}

resource "aws_ecr_repository" "store" {
  name = "coubee-be-store"
}

resource "aws_ecr_repository" "notification" {
  name = "coubee-be-notification"
}

resource "aws_ecr_repository" "order" {
  name = "coubee-be-order"
}
