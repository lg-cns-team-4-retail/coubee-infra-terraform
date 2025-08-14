# 1. VPC
resource "aws_vpc" "coubee" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support    = true
  enable_dns_hostnames  = true
  tags = {
    Name = "coubee_vpc"
  }
}

resource "aws_default_route_table" "default_rt" {
  default_route_table_id = aws_vpc.coubee.default_route_table_id

  tags = {
    Name = "coubee-default-rtb"
  }
}

# 2. 인터넷 게이트웨이
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee_igw"
  }
}

# 3. 서브넷 
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.coubee.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "coubee-subnet-public1-ap-northeast-2a"
  }
}

resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.coubee.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-2a"
  tags = {
    Name = "coubee-subnet-private1-ap-northeast-2a"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.coubee.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-northeast-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "coubee-subnet-public2-ap-northeast-2b"
  }
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.coubee.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "ap-northeast-2b"
  tags = {
    Name = "coubee-subnet-private2-ap-northeast-2b"
  }
}


# 4. 퍼블릭 라우팅 테이블 (인터넷 게이트웨이 연결)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee-rtb-public"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2_assoc" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

#5. nat gateway (AZ별로)
resource "aws_eip" "nat_a"{
  domain = "vpc"
  tags = {
    Name = "coubee-nat-eip-2a"
  }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public1.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "coubee-nat-public1-ap-northeast-2a"
  }
}

resource "aws_eip" "nat_b"{
  domain = "vpc"
  tags = {
    Name = "coubee-nat-eip-2b"
  }
}

resource "aws_nat_gateway" "nat_b"{
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public2.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "coubee-nat-public2-ap-northeast-2b"
  }
}

# 6. 프라이빗 라우팅 테이블
resource "aws_route_table" "private_a"{
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee-rtb-private1-ap-northeast-2a"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
}

resource "aws_route_table_association" "private1_assoc" {
  subnet_id = aws_subnet.private1.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee-private2-ap-northeast-2b"
  }
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
}

resource "aws_route_table_association" "private2_assoc" {
  subnet_id = aws_subnet.private2.id
  route_table_id = aws_route_table.private_b.id
}


# EventBridge Interface VPC Endpoint
resource "aws_vpc_endpoint" "eventbridge" {
  vpc_id             = aws_vpc.coubee.id
  service_name       = "com.amazonaws.ap-northeast-2.events" # EventBridge
  vpc_endpoint_type  = "Interface"

  # 엔드포인트가 붙을 서브넷 (private1만 지정)
  subnet_ids         = [aws_subnet.private1.id]

  # 엔드포인트에 연결할 SG
  security_group_ids = [aws_security_group.ec2_sg.id]

  # Private DNS 활성화
  private_dns_enabled = true

  tags = {
    Name = "vpce-eventbridge"
  }
}
