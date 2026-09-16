# Destroy AWS Resources After Assessment

Use this guide after the project is fully assessed and all screenshots/evidence are saved.

The safe order is:

```text
1. Destroy production infrastructure
2. Verify expensive resources are gone
3. Destroy Terraform backend only when you no longer need remote state
4. Optionally clean up Cloudflare
```

Do not destroy the backend first. The production Terraform state is stored in the backend bucket.

## 1. Destroy Production Infrastructure

Go to the production Terraform folder:

```bash
cd ~/devops-bootcamp-project/terraform/envs/prod
```

Initialize Terraform:

```bash
terraform init
```

Preview what will be destroyed:

```bash
terraform plan -destroy
```

Destroy production resources:

```bash
terraform destroy
```

This should remove:

- EC2 web instance
- EC2 controller instance
- EC2 monitoring instance
- Elastic IP
- security groups
- route tables
- subnets
- VPC
- ECR repository
- IAM roles and policies
- Ansible SSM S3 bucket

## 2. If ECR Blocks Destroy

Terraform may fail to delete ECR if the repository still has images.

List images:

```bash
aws ecr list-images \
  --region ap-southeast-1 \
  --repository-name devops-bootcamp/final-project-hadiyahya \
  --output json
```

Save image IDs:

```bash
aws ecr list-images \
  --region ap-southeast-1 \
  --repository-name devops-bootcamp/final-project-hadiyahya \
  --query 'imageIds' \
  --output json > /tmp/devops-ecr-images.json
```

Delete images:

```bash
aws ecr batch-delete-image \
  --region ap-southeast-1 \
  --repository-name devops-bootcamp/final-project-hadiyahya \
  --image-ids file:///tmp/devops-ecr-images.json
```

Then retry:

```bash
terraform destroy
```

## 3. Verify Expensive Resources Are Gone

Check EC2 instances:

```bash
aws ec2 describe-instances \
  --region ap-southeast-1 \
  --filters Name=tag:Project,Values=devops-bootcamp \
  --output table
```

Check Elastic IPs:

```bash
aws ec2 describe-addresses \
  --region ap-southeast-1 \
  --output table
```

Check NAT Gateways:

```bash
aws ec2 describe-nat-gateways \
  --region ap-southeast-1 \
  --filter Name=tag:Project,Values=devops-bootcamp \
  --output table
```

Check ECR:

```bash
aws ecr describe-repositories \
  --region ap-southeast-1 \
  --repository-names devops-bootcamp/final-project-hadiyahya
```

Expected:

- no running project EC2 instances
- no project Elastic IP
- no project NAT Gateway
- ECR repository deleted, or command returns repository not found

## 4. Destroy Terraform Backend Last

Only do this when you are sure you do not need the remote state anymore.

Go to the bootstrap folder:

```bash
cd ~/devops-bootcamp-project/terraform/bootstrap
```

Initialize Terraform:

```bash
terraform init
```

Destroy backend resources:

```bash
terraform destroy
```

This removes:

- Terraform state S3 bucket
- DynamoDB lock table

## 5. If Backend Bucket Blocks Destroy

The backend bucket has versioning enabled, so `terraform destroy` may fail if object versions remain.

Try removing current objects first:

```bash
aws s3 rm s3://devops-bootcamp-terraform-hadiyahya --recursive
```

If versioned objects remain, list and delete them in the S3 console:

```text
S3 -> devops-bootcamp-terraform-hadiyahya -> Versions -> permanently delete all object versions and delete markers
```

Then retry:

```bash
terraform destroy
```

## 6. Optional Cloudflare Cleanup

Cloudflare DNS records and tunnels do not create AWS cost, but you can remove them for a clean account.

Optional cleanup:

- Delete DNS record `web.hadiyahyalab.com`
- Delete DNS record or tunnel route for `monitoring.hadiyahyalab.com`
- Delete Cloudflare Tunnel `hadiyahyalab-monitoring`

## 7. Final Cost Check

Use AWS Console Billing and these CLI checks:

```bash
aws ec2 describe-instances --region ap-southeast-1 --output table
aws ec2 describe-addresses --region ap-southeast-1 --output table
aws ecr describe-repositories --region ap-southeast-1 --output table
aws s3 ls
```

Focus especially on:

- EC2 instances
- Elastic IPs
- NAT Gateways
- EBS volumes
- ECR storage
- S3 buckets

When in doubt, check the AWS console for the `devops-bootcamp` tag.
