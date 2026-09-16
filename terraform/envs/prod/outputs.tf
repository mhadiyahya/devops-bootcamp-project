output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = var.aws_region
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "web_public_ip" {
  value = aws_eip.web.public_ip
}

output "web_url" {
  value = "http://web.${var.domain_name}"
}

output "monitoring_url" {
  value = "https://monitoring.${var.domain_name}"
}

output "web_instance_id" {
  value = aws_instance.web.id
}

output "controller_instance_id" {
  value = aws_instance.controller.id
}

output "monitoring_instance_id" {
  value = aws_instance.monitoring.id
}

output "ansible_ssm_bucket" {
  value = aws_s3_bucket.ansible_ssm.bucket
}
