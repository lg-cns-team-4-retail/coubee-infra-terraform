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
resource "aws_internet_gateway" "coubee" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee_igw"
  }
}

# 3. 서브넷 (모두 하나의 AZ)
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

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.coubee.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-2a"
  tags = {
    Name = "coubee-subnet-private2-ap-northeast-2a"
  }
}

# 새로운 Private 서브넷 (ap-northeast-2b) - eks생성위해서 다른 AZ에 생성
resource "aws_subnet" "private3" {
  vpc_id            = aws_vpc.coubee.id
  cidr_block        = "10.0.4.0/24" # 기존과 겹치지 않도록 설정
  availability_zone = "ap-northeast-2b"
  tags = {
    Name = "coubee-subnet-private3-ap-northeast-2b"
  }
}

# Private3를 Private 라우팅 테이블에 연결
resource "aws_route_table_association" "private3_assoc" {
  subnet_id      = aws_subnet.private3.id
  route_table_id = aws_route_table.private.id
}

# 4. 퍼블릭 라우팅 테이블 (인터넷 게이트웨이 연결)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee-rtb-public"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coubee.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

# 5. NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "coubee-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1.id
  depends_on    = [aws_internet_gateway.coubee]
  tags = {
    Name = "coubee-nat-public1-ap-northeast-2a"
  }
}

# 6. 프라이빗 라우팅 테이블 (단일)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.coubee.id
  tags = {
    Name = "coubee-rtb-private-ap-northeast-2a"
  }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private1_assoc" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2_assoc" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_default_route_table.default_rt.id
}
