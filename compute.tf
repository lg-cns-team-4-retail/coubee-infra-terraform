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