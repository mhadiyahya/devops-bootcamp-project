# Phase 2: Implementation, Code, And Verification

This phase shows how to build the project. Code blocks include comments so you can understand what each part is doing.

## 1. Create The Repository Structure

```bash
# Create the main project folders.
mkdir -p app ansible docs scripts terraform/bootstrap terraform/envs/prod .github/workflows

# Start Git history.
git init

# Check the empty worktree.
git status
```

Why:

- folder separation makes the project easier to assess
- Git history proves the project was built progressively

## 2. Add The Preflight Script

Create:

```text
scripts/preflight-check.sh
```

Core logic:

```bash
#!/usr/bin/env bash

# Avoid accidental unset variables.
set -u

# Default region. The user can override this with --region.
REGION="ap-southeast-1"

# Track failures without exiting immediately.
FAILURES=0

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

# Check GitHub CLI authentication.
if gh auth status >/tmp/gh-status.log 2>&1; then
  pass "GitHub CLI authenticated"
else
  fail "GitHub CLI is not authenticated"
fi

# Check AWS identity.
if aws sts get-caller-identity --region "$REGION" >/tmp/aws-identity.json 2>&1; then
  pass "AWS identity is valid"
else
  fail "AWS credentials are invalid or expired"
fi

# Return non-zero when anything failed.
if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
```

Run:

```bash
chmod +x scripts/preflight-check.sh
./scripts/preflight-check.sh
```

Verification:

```text
PASS: Preflight passed
```

## 3. Bootstrap Terraform Backend

Create:

```text
terraform/bootstrap/main.tf
```

Code:

```hcl
provider "aws" {
  # Keep the project in the required region.
  region = var.aws_region
}

locals {
  # The suffix keeps names unique in your AWS account.
  backend_bucket = "devops-bootcamp-terraform-${var.project_suffix}"
  lock_table     = "devops-bootcamp-terraform-lock-${var.project_suffix}"
}

resource "aws_s3_bucket" "terraform_state" {
  # Stores Terraform state remotely.
  bucket = local.backend_bucket
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  # State files can contain sensitive infrastructure data, so block public access.
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  # Versioning allows recovery from accidental state overwrites.
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  # Terraform uses this table to avoid two applies at the same time.
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

Create:

```text
terraform/bootstrap/variables.tf
```

Code:

```hcl
variable "aws_region" {
  description = "AWS region for backend resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_suffix" {
  description = "Unique suffix for resource names"
  type        = string
  default     = "hadiyahya"
}
```

Run:

```bash
cd terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply
```

Assessment evidence:

- S3 bucket screenshot
- DynamoDB table screenshot
- Terraform output screenshot

## 4. Configure Production Terraform Backend

Create:

```text
terraform/envs/prod/versions.tf
```

Code:

```hcl
terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    # Remote state bucket created by terraform/bootstrap.
    bucket = "devops-bootcamp-terraform-hadiyahya"

    # State path for this environment.
    key = "prod/terraform.tfstate"

    region = "ap-southeast-1"

    # Lock table created by terraform/bootstrap.
    dynamodb_table = "devops-bootcamp-terraform-lock-hadiyahya"

    # Encrypt state at rest.
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

Note:

Terraform shows a warning that `dynamodb_table` is deprecated in newer versions. It still works, but later you can migrate to `use_lockfile`.

## 5. Add Production Variables

Create:

```text
terraform/envs/prod/variables.tf
```

Code:

```hcl
variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project_suffix" {
  type    = string
  default = "hadiyahya"
}

variable "domain_name" {
  type    = string
  default = "hadiyahyalab.com"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
```

Why:

- variables make names and region easy to change
- defaults match the assessment environment

## 6. Add VPC, Subnets, And Routes

Add to:

```text
terraform/envs/prod/main.tf
```

Code:

```hcl
provider "aws" {
  region = var.aws_region
}

locals {
  project_name = "devops-bootcamp"

  common_tags = {
    Project = local.project_name
    Owner   = var.project_suffix
    Domain  = var.domain_name
  }
}

resource "aws_vpc" "main" {
  # Small VPC for the bootcamp project.
  cidr_block = "10.0.0.0/24"

  # Required so private DNS names resolve inside the VPC.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "devops-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  # Gives the public subnet a path to the internet.
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/25"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = "${var.aws_region}a"
}
```

Then add public route:

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    # Send all non-local traffic to the Internet Gateway.
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

Private route will be added after the web instance exists because it needs the web network interface ID.

## 7. Add Security Groups

Code:

```hcl
resource "aws_security_group" "web" {
  name        = "devops-public-sg"
  description = "Public web server security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    # Public users reach the app on HTTP.
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    # Monitoring server scrapes web metrics.
    description     = "node_exporter from monitoring"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.private.id]
  }

  ingress {
    # Private servers send traffic through web as NAT.
    description     = "NAT traffic from private servers"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.private.id]
  }

  egress {
    description = "Outbound internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private" {
  name        = "devops-private-sg"
  description = "Private server security group"
  vpc_id      = aws_vpc.main.id

  egress {
    # Private instances can initiate outbound traffic.
    description = "Outbound through web NAT instance"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "private_self_all" {
  # Allows controller and monitoring to talk inside the private SG.
  type                     = "ingress"
  description              = "Private subnet east-west traffic"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.private.id
  source_security_group_id = aws_security_group.private.id
}
```

Assessment point:

No SSH port is opened.

## 8. Add IAM Roles

Code:

```hcl
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
}

resource "aws_iam_role" "controller" {
  name               = "devops-controller-role-${var.project_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role" "monitoring" {
  name               = "devops-monitoring-role-${var.project_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}
```

Attach SSM:

```hcl
resource "aws_iam_role_policy_attachment" "ssm_core" {
  # Every EC2 instance needs SSM permissions.
  for_each = {
    web        = aws_iam_role.web.name
    controller = aws_iam_role.controller.name
    monitoring = aws_iam_role.monitoring.name
  }

  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

ECR read policy:

```hcl
data "aws_iam_policy_document" "ecr_read" {
  statement {
    # AWS requires this action to use resource "*".
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    # These actions are scoped to the project ECR repository.
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}
```

## 9. Add ECR

Code:

```hcl
resource "aws_ecr_repository" "app" {
  # Private repository for the app image.
  name                 = "devops-bootcamp/final-project-${var.project_suffix}"
  image_tag_mutability = "MUTABLE"

  # Scan images when pushed.
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

Why:

The rubric asks for an image built and pushed to private ECR.

## 10. Add EC2 And One-EIP NAT

Common user data:

```hcl
locals {
  common_user_data = <<-EOF
    #!/usr/bin/env bash
    set -euxo pipefail

    # Basic tools needed by SSM, Ansible, scripts, and troubleshooting.
    apt-get update
    apt-get install -y snapd unzip curl ca-certificates python3 python3-pip python3-boto3 python3-botocore

    # Install and start SSM agent.
    snap install amazon-ssm-agent --classic || true
    systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || systemctl enable --now amazon-ssm-agent || true
  EOF
}
```

Web NAT user data:

```hcl
locals {
  web_user_data = <<-EOF
    ${local.common_user_data}

    # Enable Linux packet forwarding now and after reboot.
    sysctl -w net.ipv4.ip_forward=1
    echo net.ipv4.ip_forward=1 > /etc/sysctl.d/99-devops-nat.conf

    # Script that ensures private subnet traffic is NATed through this instance.
    cat >/usr/local/sbin/devops-apply-nat.sh <<'SCRIPT'
    #!/usr/bin/env bash
    set -euo pipefail
    sysctl -w net.ipv4.ip_forward=1
    iptables -t nat -C POSTROUTING -s 10.0.0.128/25 -o ens5 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.0.0.128/25 -o ens5 -j MASQUERADE
    SCRIPT

    chmod +x /usr/local/sbin/devops-apply-nat.sh

    # systemd restores the NAT rule after reboot.
    cat >/etc/systemd/system/devops-nat.service <<'UNIT'
    [Unit]
    Description=DevOps Bootcamp NAT for private subnet
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/devops-apply-nat.sh
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now devops-nat.service
  EOF
}
```

EC2 instances:

```hcl
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = "10.0.0.5"
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.web.name
  user_data                   = local.web_user_data
  associate_public_ip_address = true

  # Required because the instance forwards private subnet traffic.
  source_dest_check = false
}

resource "aws_eip" "web" {
  # The only Elastic IP in the project.
  domain = "vpc"
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
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  private_ip             = "10.0.0.136"
  vpc_security_group_ids = [aws_security_group.private.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name
}
```

Add private route after web exists:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    # Send private outbound traffic through the web instance ENI.
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.web.primary_network_interface_id
  }
}
```

## 11. Add Terraform Outputs

Create:

```text
terraform/envs/prod/outputs.tf
```

Code:

```hcl
output "web_public_ip" {
  value = aws_eip.web.public_ip
}

output "web_url" {
  value = "http://web.${var.domain_name}"
}

output "monitoring_url" {
  value = "https://monitoring.${var.domain_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
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
```

Why:

Outputs become inputs for Ansible, scripts, documentation, and manual DNS setup.

## 12. Apply Production Terraform

```bash
cd terraform/envs/prod

# Download providers and connect to remote backend.
terraform init

# Check formatting.
terraform fmt -check

# Check syntax and provider schema.
terraform validate

# Preview before creating resources.
terraform plan

# Create resources.
terraform apply

# Print important IDs and URLs.
terraform output
```

Verify one EIP:

```bash
aws ec2 describe-addresses --region ap-southeast-1 --output table
```

Verify SSM:

```bash
aws ssm describe-instance-information --region ap-southeast-1 --output table
```

## 13. Add Dockerfile

Create:

```text
app/Dockerfile
```

Code:

```dockerfile
# Build stage: use Node to install dependencies, test, and build static files.
FROM node:22-alpine AS build

WORKDIR /app

# Copy package files first to improve Docker layer caching.
COPY package*.json ./
RUN npm ci

# Copy the app source and build it.
COPY . .
RUN npm test && npm run build

# Runtime stage: Nginx serves only the built static files.
FROM nginx:1.27-alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# Healthcheck lets Docker report if the app stops responding.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
```

Build locally:

```bash
cd app
docker build -t final-project-app .
```

## 14. Add Ansible Inventory

Create:

```text
ansible/inventory.aws_ec2.yml
```

Concept:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - ap-southeast-1
filters:
  tag:Project: devops-bootcamp
  instance-state-name: running
keyed_groups:
  # Turns EC2 Role tags into Ansible groups such as role_web.
  - key: tags.Role
    prefix: role
```

Why:

Ansible targets EC2 instances by tags, not hardcoded public IPs.

## 15. Add Ansible Playbook

Create:

```text
ansible/playbooks/site.yml
```

Code:

```yaml
---
# Configure the public web server.
- name: Configure web server
  hosts: role_web
  become: true
  roles:
    - common
    - geerlingguy.docker
    - web_app

# Configure metrics on the private controller.
- name: Configure controller metrics
  hosts: role_controller
  become: true
  roles:
    - common
    - geerlingguy.docker
    - node_exporter

# Configure Prometheus and Grafana on private monitoring.
- name: Configure monitoring server
  hosts: role_monitoring
  become: true
  roles:
    - common
    - geerlingguy.docker
    - monitoring
```

Why:

Each play maps directly to a server role.

## 16. Add Web App Role

Create:

```text
ansible/roles/web_app/tasks/main.yml
```

Code:

```yaml
---
- name: Require ECR repository URL
  ansible.builtin.assert:
    that:
      - ecr_repository_url | length > 0
    fail_msg: "Set ecr_repository_url from Terraform output before running this playbook."

- name: Log in Docker to Amazon ECR
  ansible.builtin.shell: |
    set -euo pipefail
    aws ecr get-login-password --region {{ aws_region }} |
      docker login --username AWS --password-stdin {{ ecr_repository_url | regex_replace('/.*$', '') }}
  args:
    executable: /bin/bash
  # Login may refresh credentials but should not count as app config drift.
  changed_when: false

- name: Run application container
  community.docker.docker_container:
    name: "{{ app_container_name }}"
    image: "{{ ecr_repository_url }}:{{ app_image_tag }}"
    pull: always
    restart_policy: unless-stopped
    published_ports:
      - "{{ app_host_port }}:{{ app_container_port }}"

- name: Run node_exporter container
  community.docker.docker_container:
    name: "{{ node_exporter_container_name }}"
    image: quay.io/prometheus/node-exporter:v1.8.2
    pull: true
    restart_policy: unless-stopped
    command:
      - "--path.rootfs=/host"
    pid_mode: host
    published_ports:
      - "{{ node_exporter_port }}:9100"
    volumes:
      - "/:/host:ro,rslave"
```

Assessment:

- app runs as container
- node_exporter collects web metrics
- Ansible is idempotent

## 17. Add Monitoring Role

Create:

```text
ansible/roles/monitoring/tasks/main.yml
```

Code:

```yaml
---
- name: Create Prometheus config directory
  ansible.builtin.file:
    path: "{{ prometheus_config_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Render Prometheus configuration
  ansible.builtin.template:
    src: prometheus.yml.j2
    dest: "{{ prometheus_config_dir }}/prometheus.yml"
    owner: root
    group: root
    mode: "0644"
  notify: Restart monitoring stack

- name: Render Grafana datasource
  ansible.builtin.template:
    src: grafana-datasource.yml.j2
    dest: "{{ grafana_provisioning_dir }}/datasources/prometheus.yml"
    owner: root
    group: root
    mode: "0644"
  notify: Restart monitoring stack

- name: Render Grafana dashboard
  ansible.builtin.template:
    src: bootcamp-nodes-dashboard.json.j2
    dest: "{{ grafana_dashboards_dir }}/bootcamp-nodes.json"
    owner: root
    group: root
    mode: "0644"
  notify: Restart monitoring stack

- name: Start monitoring stack
  community.docker.docker_compose_v2:
    project_src: "{{ prometheus_config_dir }}"
    state: present
```

Why:

Grafana and Prometheus are reproducible because configs and dashboards are templates.

## 18. Add Prometheus Template

Create:

```text
ansible/roles/monitoring/templates/prometheus.yml.j2
```

Code:

```yaml
global:
  # Scrape targets every 15 seconds.
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090

  - job_name: node-exporter
    static_configs:
      - targets:
          - "10.0.0.5:9100"
        labels:
          server: web
      - targets:
          - "10.0.0.135:9100"
        labels:
          server: controller
```

Why:

The `server` label is what makes Grafana filtering possible.

## 19. Add GitHub Actions

Terraform plan workflow:

```yaml
name: Terraform Plan

on:
  pull_request:
    paths:
      - "terraform/**"
      - ".github/workflows/terraform-plan.yml"
  workflow_dispatch:

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform/envs/prod

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v5
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-southeast-1

      - name: Terraform fmt
        run: terraform fmt -check -recursive ../..

      - name: Terraform init
        run: terraform init

      - name: Terraform validate
        run: terraform validate

      - name: Terraform plan
        run: terraform plan -input=false
```

Docker image workflow:

```yaml
name: Build And Push App Image

on:
  push:
    branches:
      - main
    paths:
      - "app/**"
  workflow_dispatch:

env:
  AWS_REGION: ap-southeast-1
  ECR_REPOSITORY: devops-bootcamp/final-project-hadiyahya

jobs:
  image:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v5
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push image
        working-directory: app
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t "$REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" -t "$REGISTRY/$ECR_REPOSITORY:latest" .
          docker push "$REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
          docker push "$REGISTRY/$ECR_REPOSITORY:latest"
```

## 20. Configure Cloudflare

Web DNS:

```text
Type: A
Name: web
Target: <terraform output web_public_ip>
```

Monitoring Tunnel concept:

```yaml
# Cloudflare tunnel ingress example.
ingress:
  - hostname: monitoring.hadiyahyalab.com
    service: http://localhost:3000
  - service: http_status:404
```

Why:

- web uses DNS to the Elastic IP
- monitoring stays private and is reached through tunnel

## 21. Verify Everything

Terraform:

```bash
terraform -chdir=terraform/envs/prod fmt -check
terraform -chdir=terraform/envs/prod validate
cd terraform/envs/prod && terraform plan -detailed-exitcode
```

SSM:

```bash
aws ssm describe-instance-information --region ap-southeast-1 --output table
```

Web:

```bash
curl -I http://web.hadiyahyalab.com
```

Monitoring:

```bash
curl -I https://monitoring.hadiyahyalab.com
```

Prometheus:

```bash
./scripts/ssm-run.sh <monitoring-instance-id> \
  "curl -sf 'http://localhost:9090/api/v1/query?query=up'"
```

Expected Prometheus result:

```text
web target = 1
controller target = 1
prometheus target = 1
```

## 22. Assessment Evidence Checklist

Capture:

- `scripts/preflight-check.sh` pass
- Terraform backend resources
- Terraform outputs
- VPC and subnets
- public/private route tables
- only one Elastic IP
- EC2 private IPs
- SSM managed instances
- ECR image
- app URL
- Cloudflare DNS record
- Cloudflare Tunnel
- Prometheus targets
- Grafana dashboard
- GitHub Actions runs
- branch protection with `terraform`
- GitHub Pages
- 121/122 HTTPS enforcement remark
