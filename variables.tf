variable "project_name" {
  description = "프로젝트 이름 (태그 prefix 등으로 사용)"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
}

variable "availability_zone" {
  description = "기본 가용 영역"
  type        = string
}

variable "key_name" {
  description = "EC2 인스턴스에 사용할 키페어 이름"
  type        = string
}

variable "ami_id" {
  description = "Ubuntu 22.04 AMI ID (서울 리전)"
  type        = string
}

# VPC/서브넷 관련
variable "vpc_cidr_block" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "public_cidr_block" {
  description = "퍼블릭 서브넷 CIDR"
  type        = string
}

variable "private1_cidr_block" {
  description = "프라이빗 서브넷1 CIDR"
  type        = string
}

variable "private2_cidr_block" {
  description = "프라이빗 서브넷2 CIDR"
  type        = string
}

# EC2 인스턴스 타입 변수들
variable "bastion_instance_type" {
  description = "Bastion 용 EC2 인스턴스 타입"
  type        = string
}

variable "kafka_instance_type" {
  description = "kafka 용 EC2 인스턴스 타입"
  type        = string
}

variable "jenkins_instance_type" {
  description = "Jenkins 용 EC2 인스턴스 타입"
  type        = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
  sensitive = true
}

variable "db_instance_type" {
  type = string
}