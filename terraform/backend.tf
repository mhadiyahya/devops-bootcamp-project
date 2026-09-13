terraform {
  backend "s3" {
    bucket       = "devops-bootcamp-terraform-mhadiyahya"
    key          = "devops-bootcamp-project/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}