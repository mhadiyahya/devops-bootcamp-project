# Ubuntu 24.04 ami
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Web Server
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id  = aws_subnet.public_subnet.id
  private_ip = "10.0.0.5"

  vpc_security_group_ids = [
    aws_security_group.public_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = {
    Name    = "devops-web-server"
    Project = "mhadiyahya"
  }
}

# Ansible (Controller)
resource "aws_instance" "controller" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.private_subnet.id
  private_ip                  = "10.0.0.135"
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.private_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = {
    Name    = "devops-controller"
    Project = "mhadiyahya"
  }
}

# Monitoring Server
resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.private_subnet.id
  private_ip                  = "10.0.0.136"
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.private_sg.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = {
    Name    = "devops-monitoring"
    Project = "mhadiyahya"
  }
}
