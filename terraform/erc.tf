resource "aws_ecr_repository" "application" {
  name                 = "devops-bootcamp/final-project-mhadiyahya"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "devops-bootcamp-final-project-mhadiyahya"
    Project = "mhadiyahya"
  }
}

output "ecr_repository_url" {
  description = "URL of the private ECR repository"
  value       = aws_ecr_repository.application.repository_url
}