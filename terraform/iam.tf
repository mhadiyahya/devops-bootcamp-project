# Author: Hadi Yahya
# Date: 2026-09-13
# Project: DevOps Bootcamp Project

# DevOps AWS IAM

# Create IAM Role
resource "aws_iam_role" "ssm_role" {
  name = "devops-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = "mhadiyahya"
  }
}

# Attach SSM Policy
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create Instance Profile
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "devops-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}