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