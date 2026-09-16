provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  project_name = "devops-bootcamp"
  ecr_name     = "devops-bootcamp/final-project-${var.project_suffix}"

  common_tags = {
    Project = local.project_name
    Owner   = var.project_suffix
    Domain  = var.domain_name
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "devops-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "devops-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/25"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "devops-public-subnet"
  })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = "${var.aws_region}a"

  tags = merge(local.common_tags, {
    Name = "devops-private-subnet"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "devops-ngw-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(local.common_tags, {
    Name = "devops-ngw"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "devops-public-route"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "devops-private-route"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "web" {
  name        = "devops-public-sg"
  description = "Public web server security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "node_exporter from monitoring"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.private.id]
  }

  egress {
    description = "Outbound internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "devops-public-sg"
  })
}

resource "aws_security_group" "private" {
  name        = "devops-private-sg"
  description = "Private server security group"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Outbound through NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "devops-private-sg"
  })
}

resource "aws_security_group_rule" "private_self_all" {
  type                     = "ingress"
  description              = "Private subnet east-west traffic"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.private.id
  source_security_group_id = aws_security_group.private.id
}

resource "aws_ecr_repository" "app" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = local.ecr_name
  })
}

resource "aws_s3_bucket" "ansible_ssm" {
  bucket = "devops-bootcamp-ansible-ssm-${var.project_suffix}-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "devops-bootcamp-ansible-ssm-${var.project_suffix}"
  })
}

resource "aws_s3_bucket_public_access_block" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "devops-web-role-${var.project_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role" "controller" {
  name               = "devops-controller-role-${var.project_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role" "monitoring" {
  name               = "devops-monitoring-role-${var.project_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each = {
    web        = aws_iam_role.web.name
    controller = aws_iam_role.controller.name
    monitoring = aws_iam_role.monitoring.name
  }

  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ecr_read" {
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "controller_ssm_ansible" {
  statement {
    actions = [
      "ssm:DescribeInstanceInformation",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.ansible_ssm.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ansible_ssm.arn]
  }
}

resource "aws_iam_policy" "ecr_read" {
  name   = "devops-ecr-read-${var.project_suffix}"
  policy = data.aws_iam_policy_document.ecr_read.json
  tags   = local.common_tags
}

resource "aws_iam_policy" "controller_ssm_ansible" {
  name   = "devops-controller-ssm-ansible-${var.project_suffix}"
  policy = data.aws_iam_policy_document.controller_ssm_ansible.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "web_ecr_read" {
  role       = aws_iam_role.web.name
  policy_arn = aws_iam_policy.ecr_read.arn
}

resource "aws_iam_role_policy_attachment" "controller_ecr_read" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.ecr_read.arn
}

resource "aws_iam_role_policy_attachment" "controller_ssm_ansible" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller_ssm_ansible.arn
}

resource "aws_iam_instance_profile" "web" {
  name = "devops-web-profile-${var.project_suffix}"
  role = aws_iam_role.web.name
}

resource "aws_iam_instance_profile" "controller" {
  name = "devops-controller-profile-${var.project_suffix}"
  role = aws_iam_role.controller.name
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "devops-monitoring-profile-${var.project_suffix}"
  role = aws_iam_role.monitoring.name
}

locals {
  common_user_data = <<-EOF
    #!/usr/bin/env bash
    set -euxo pipefail
    apt-get update
    apt-get install -y snapd unzip curl ca-certificates python3 python3-pip python3-boto3 python3-botocore
    snap install amazon-ssm-agent --classic || true
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || systemctl enable --now amazon-ssm-agent || true
  EOF

  controller_user_data = <<-EOF
    ${local.common_user_data}
    apt-get install -y git ansible
    ansible-galaxy collection install amazon.aws community.docker
    ansible-galaxy role install geerlingguy.docker
  EOF
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = "10.0.0.5"
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.web.name
  user_data                   = local.common_user_data
  associate_public_ip_address = true

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "devops-web-server"
    Role = "web"
  })
}

resource "aws_eip" "web" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "devops-web-eip"
  })
}

resource "aws_eip_association" "web" {
  allocation_id = aws_eip.web.id
  instance_id   = aws_instance.web.id
}

resource "aws_instance" "controller" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  private_ip             = "10.0.0.135"
  vpc_security_group_ids = [aws_security_group.private.id]
  iam_instance_profile   = aws_iam_instance_profile.controller.name
  user_data              = local.controller_user_data

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "devops-ansible-controller"
    Role = "controller"
  })
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  private_ip             = "10.0.0.136"
  vpc_security_group_ids = [aws_security_group.private.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name
  user_data              = local.common_user_data

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "devops-monitoring-server"
    Role = "monitoring"
  })
}
