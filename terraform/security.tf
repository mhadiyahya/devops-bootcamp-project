# Author: Hadi Yahya
# Date: 2026-09-13
# Project: DevOps Bootcamp Project

# DevOps AWS Security

# Security Public Group
resource "aws_security_group" "public_sg" {
  name        = "devops-public-sg"
  description = "Security group for public web server"
  vpc_id      = aws_vpc.devops_vpc.id

  tags = {
    Name    = "devops-public-sg"
    Project = "mhadiyahya"
  }
}

# Rule allow incoming port 80 from Internet
resource "aws_vpc_security_group_ingress_rule" "public_http" {
  security_group_id = aws_security_group.public_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP from Internet"
}

# Rule allow monitoring server to access Node Exporter
resource "aws_vpc_security_group_ingress_rule" "public_node_exporter" {
  security_group_id = aws_security_group.public_sg.id

  cidr_ipv4   = "10.0.0.136/32"
  from_port   = 9100
  to_port     = 9100
  ip_protocol = "tcp"

  description = "Allow monitoring server to access Node Exporter"
}

# Rule allow Egress public traffic
resource "aws_vpc_security_group_egress_rule" "public_egress" {
  security_group_id = aws_security_group.public_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  description = "Allow all outbound traffic"
}

# Private Security Group
resource "aws_security_group" "private_sg" {
  name        = "devops-private-sg"
  description = "Security group for private servers"
  vpc_id      = aws_vpc.devops_vpc.id

  tags = {
    Name    = "devops-private-sg"
    Project = "mhadiyahya"
  }
}

# Rule allow Egress private traffic
resource "aws_vpc_security_group_egress_rule" "private_egress" {
  security_group_id = aws_security_group.private_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  description = "Allow outbound traffic"
}

# Allow private SSH from Ansible Controller to Web Server

resource "aws_vpc_security_group_ingress_rule" "public_ssh_from_controller" {
  security_group_id = aws_security_group.public_sg.id

  cidr_ipv4   = "10.0.0.135/32"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  description = "Allow SSH from Ansible Controller"
}

# Allow private SSH from Ansible Controller to Monitoring Server

resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_controller" {
  security_group_id = aws_security_group.private_sg.id

  cidr_ipv4   = "10.0.0.135/32"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  description = "Allow SSH from Ansible Controller"
}