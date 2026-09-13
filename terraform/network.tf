# Author: Hadi Yahya
# Date: 2026-09-13
# Project: DevOps Bootcamp Project

# DevOps AWS VPC

resource "aws_vpc" "devops_vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "devops-vpc"
    Project = "mhadiyahya"
  }
}

# Public Subnet

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.0.0/25"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "devops-public-subnet"
    Project = "mhadiyahya"
  }
}

# Private Subnet

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.devops_vpc.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name    = "devops-private-subnet"
    Project = "mhadiyahya"
  }
}

# IGW

resource "aws_internet_gateway" "devops_igw" {
  vpc_id = aws_vpc.devops_vpc.id

  tags = {
    Name    = "devops-igw"
    Project = "mhadiyahya"
  }
}

# Public Route

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops_igw.id
  }

  tags = {
    Name    = "devops-public-route"
    Project = "mhadiyahya"
  }
}

# Public Route Association

resource "aws_route_table_association" "public_route_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route.id
}

# Elastic IP
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name    = "devops-nat-eip"
    Project = "mhadiyahya"
  }
}

# NAT Gateway

resource "aws_nat_gateway" "devops_ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [
    aws_internet_gateway.devops_igw
  ]

  tags = {
    Name    = "devops-ngw"
    Project = "mhadiyahya"
  }
}

# Private Route Table

resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.devops_ngw.id
  }

  tags = {
    Name    = "devops-private-route"
    Project = "mhadiyahya"
  }
}

# Private Subnet ke Route Table

resource "aws_route_table_association" "private_route_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route.id
}

# Web Server IP
resource "aws_eip" "web_eip" {
  domain = "vpc"

  tags = {
    Name    = "devops-web-eip"
    Project = "mhadiyahya"
  }
}

resource "aws_eip_association" "web_eip_association" {
  instance_id   = aws_instance.web_server.id
  allocation_id = aws_eip.web_eip.id
}