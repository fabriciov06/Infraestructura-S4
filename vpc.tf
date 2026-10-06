# --- VPC PRINCIPAL ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "image-processor-${var.environment}-vpc"
  }
}

# --- INTERNET GATEWAY ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "image-processor-${var.environment}-igw"
  }
}

# --- ELASTIC IPS PARA NAT GATEWAYS ---
resource "aws_eip" "nat_a" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = { Name = "image-processor-${var.environment}-eip-nat-a" }
}

resource "aws_eip" "nat_b" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = { Name = "image-processor-${var.environment}-eip-nat-b" }
}

# --- SUBREDES PÚBLICAS ---
resource "aws_subnet" "pub_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "image-processor-${var.environment}-pub-a" }
}

resource "aws_subnet" "pub_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "image-processor-${var.environment}-pub-b" }
}

# --- NAT GATEWAYS ---
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.pub_a.id
  tags = { Name = "image-processor-${var.environment}-nat-a" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.pub_b.id
  tags = { Name = "image-processor-${var.environment}-nat-b" }
}

# --- SUBREDES PRIVADAS ---
resource "aws_subnet" "priv_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "image-processor-${var.environment}-priv-a" }
}

resource "aws_subnet" "priv_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "image-processor-${var.environment}-priv-b" }
}

# --- TABLAS DE ENRUTAMIENTO ---
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "image-processor-${var.environment}-rt-public" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table" "priv_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  tags = { Name = "image-processor-${var.environment}-rt-priv-a" }
}

resource "aws_route_table" "priv_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "image-processor-${var.environment}-rt-priv-b" }
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.priv_a.id
  route_table_id = aws_route_table.priv_a.id
}

resource "aws_route_table_association" "priv_b" {
  subnet_id      = aws_subnet.priv_b.id
  route_table_id = aws_route_table.priv_b.id
}

# --- SECURITY GROUP PARA LAS LAMBDAS ---
resource "aws_security_group" "lambda_sg" {
  name        = "image-processor-${var.environment}-lambda-sg"
  description = "Security group for lambda inside vpc"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "image-processor-${var.environment}-lambda-sg" }
}

# --- VPC ENDPOINT S3 (GATEWAY) ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.priv_a.id, aws_route_table.priv_b.id]
  tags = { Name = "image-processor-${var.environment}-vpce-s3" }
}

# --- VPC ENDPOINT SQS (INTERFACE) ---
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.priv_a.id, aws_subnet.priv_b.id]
  security_group_ids  = [aws_security_group.lambda_sg.id]
  private_dns_enabled = true
  tags = { Name = "image-processor-${var.environment}-vpce-sqs" }
}