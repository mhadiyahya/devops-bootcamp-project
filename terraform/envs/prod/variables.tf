variable "aws_region" {
  description = "AWS region for project resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_suffix" {
  description = "Suffix for named AWS resources."
  type        = string
  default     = "hadiyahya"
}

variable "domain_name" {
  description = "Root domain for the project."
  type        = string
  default     = "hadiyahyalab.com"
}

variable "instance_type" {
  description = "EC2 instance type for bootcamp servers."
  type        = string
  default     = "t3.micro"
}
