# A-Z Walkthrough: DevOps Bootcamp Project

This walkthrough is for rebuilding the project yourself later. It follows 5W1H so each phase explains what to do, why it matters, who/where it applies, when to do it, and how to verify it.

For a deeper build-from-zero explanation with code logic, fundamentals, and assessment checkpoints, read [`detailed-build.md`](detailed-build.md).

For a clearer two-phase learning version, read [`phased/README.md`](phased/README.md).

## Scoring Remark

Current practical score estimate: `121/122`.

The remaining 1 point is not fully claimable yet because GitHub Pages HTTPS enforcement cannot be enabled until GitHub finishes issuing the custom-domain certificate. The site works through Cloudflare at `https://hadiyahyalab.com`, but the GitHub Pages API still reports `https_enforced=false` with the message `The certificate does not exist yet`. Recheck this later in GitHub Pages settings and enable "Enforce HTTPS" once the certificate is ready.

## 0. Project Map

| Folder/File | Purpose |
| --- | --- |
| `scripts/preflight-check.sh` | Checks laptop, GitHub, AWS CLI, AWS identity, and SSM connectivity |
| `terraform/bootstrap/` | Creates Terraform remote state bucket and lock table |
| `terraform/envs/prod/` | Creates VPC, EC2, EIP, ECR, IAM, routing, and security groups |
| `app/` | Application source and Dockerfile |
| `ansible/` | Server configuration, Docker deployment, Prometheus, Grafana |
| `.github/workflows/` | CI/CD, Terraform plan gate, ECR image push, deployment, Pages |
| `docs/` | GitHub Pages documentation and evidence checklist |

## 1. Prepare The Laptop

**What:** Prepare WSL/Linux with Git, GitHub CLI, AWS CLI, Terraform, Docker, and Session Manager plugin.

**Why:** The project uses GitHub, AWS, Terraform, Docker, and SSM-first access. If the laptop is not ready, every later step becomes harder to debug.

**Who:** You, running commands from WSL Ubuntu.

**Where:** Local laptop, inside this repo.

**When:** Before creating or changing infrastructure.

**How:**

```bash
./scripts/preflight-check.sh
```

Expected result:

```text
PASS: Preflight passed
```

If AWS identity fails, fix AWS credentials first:

```bash
aws configure list
aws sts get-caller-identity
```

## 2. Bootstrap GitHub

**What:** Keep the project in a public GitHub repository.

**Why:** The rubric checks public repo, GitHub Actions, GitHub Pages, and PR plan gate.

**Who:** GitHub account `mhadiyahya`.

**Where:** GitHub repository `mhadiyahya/devops-bootcamp-project`.

**When:** Before relying on CI/CD or Pages.

**How:**

```bash
git status
git remote -v
git push
```

Verify:

```bash
gh repo view mhadiyahya/devops-bootcamp-project --web
```

## 3. Bootstrap Terraform Backend

**What:** Create the S3 backend bucket and DynamoDB lock table.

**Why:** Terraform state must be stored remotely and protected from concurrent writes.

**Who:** Your AWS IAM user creates the backend resources.

**Where:** `terraform/bootstrap/`.

**When:** Once, before running production Terraform.

**How:**

```bash
cd terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply
```

Expected resources:

- S3 bucket: `devops-bootcamp-terraform-hadiyahya`
- DynamoDB table: `devops-bootcamp-terraform-lock-hadiyahya`

## 4. Provision AWS Infrastructure

**What:** Create the VPC, subnets, routes, security groups, EC2 instances, EIP, ECR repository, and IAM roles.

**Why:** This is the infrastructure foundation for the application, Ansible, and monitoring stack.

**Who:** Terraform using AWS credentials.

**Where:** `terraform/envs/prod/`.

**When:** After backend bootstrap.

**How:**

```bash
cd terraform/envs/prod
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
```

Expected design:

- VPC: `10.0.0.0/24`
- Public subnet: `10.0.0.0/25`
- Private subnet: `10.0.0.128/25`
- Web: `10.0.0.5`, public, one Elastic IP
- Controller: `10.0.0.135`, private
- Monitoring: `10.0.0.136`, private
- Private outbound: route through the web NAT instance

Verify one Elastic IP only:

```bash
aws ec2 describe-addresses --region ap-southeast-1 --output table
```

## 5. Validate SSM Access

**What:** Confirm every instance is reachable through AWS Systems Manager.

**Why:** The project avoids SSH and uses SSM for operations and Ansible.

**Who:** Laptop to AWS SSM, then SSM to EC2 instances.

**Where:** Local repo.

**When:** After Terraform creates EC2 instances.

**How:**

```bash
./scripts/preflight-check.sh --name-tag devops-web-server
./scripts/preflight-check.sh --name-tag devops-ansible-controller
./scripts/preflight-check.sh --name-tag devops-monitoring-server
```

Quick command test:

```bash
./scripts/ssm-run.sh <instance-id> "echo ssm-ok && hostname"
```

## 6. Build And Push The Docker Image

**What:** Build the application image and push it to private ECR.

**Why:** The application must be published as a container image and deployed from ECR.

**Who:** GitHub Actions, or you locally if testing.

**Where:** `app/` and `.github/workflows/docker-image.yml`.

**When:** After ECR exists.

**How locally:**

```bash
cd app
docker build -t final-project-app .
```

**How through CI/CD:**

Run GitHub Actions workflow:

```text
Build And Push App Image
```

Verify:

```bash
aws ecr describe-images \
  --region ap-southeast-1 \
  --repository-name devops-bootcamp/final-project-hadiyahya \
  --output table
```

## 7. Deploy With Ansible

**What:** Run Ansible from the private controller to configure web and monitoring.

**Why:** This proves configuration management, idempotency, and SSM-based private administration.

**Who:** Controller instance runs Ansible.

**Where:** `ansible/`, triggered locally or by GitHub Actions.

**When:** After Terraform and ECR image push.

**How:**

```bash
./scripts/deploy-from-controller.sh
```

Or run the workflow:

```text
Deploy With Ansible Controller
```

What Ansible configures:

- Docker on all required servers
- App container on web port `80`
- node_exporter on web and controller
- Prometheus and Grafana on monitoring
- Grafana datasource and dashboard provisioning

Verify idempotency by running the deployment twice. The second run should have minimal changes.

## 8. Configure DNS And Cloudflare

**What:** Point the web domain to the web Elastic IP and expose Grafana through Cloudflare Tunnel.

**Why:** The rubric checks DNS to Elastic IP, Cloudflare Tunnel, and monitoring not publicly exposed.

**Who:** You in Cloudflare dashboard.

**Where:** Cloudflare zone `hadiyahyalab.com`.

**When:** After Terraform outputs `web_public_ip` and monitoring is running.

**How:**

Web DNS:

| Type | Name | Target |
| --- | --- | --- |
| `A` | `web` | Terraform output `web_public_ip` |

Monitoring tunnel:

| Hostname | Service |
| --- | --- |
| `monitoring.hadiyahyalab.com` | `http://localhost:3000` on the monitoring server |

Verify:

```bash
curl -I http://web.hadiyahyalab.com
curl -I https://monitoring.hadiyahyalab.com
```

Expected:

- Web returns `200`
- Monitoring returns `302` to Grafana login

## 9. Verify Monitoring

**What:** Check Prometheus targets and Grafana dashboard.

**Why:** The rubric gives many marks for correct metrics collection, Prometheus, and Grafana.

**Who:** Monitoring server collects metrics from web and controller.

**Where:** Prometheus on monitoring, Grafana through Cloudflare Tunnel.

**When:** After Ansible deployment.

**How:**

```bash
./scripts/ssm-run.sh <monitoring-instance-id> \
  "curl -sf 'http://localhost:9090/api/v1/query?query=up'"
```

Expected targets:

- `localhost:9090` Prometheus
- `10.0.0.5:9100` web node_exporter
- `10.0.0.135:9100` controller node_exporter

Grafana:

```text
https://monitoring.hadiyahyalab.com
```

Dashboard path:

```text
Dashboards -> DevOps Bootcamp -> Bootcamp Nodes - Web and Controller
```

Use the `server` filter to switch between `web`, `controller`, and `All`.

## 10. Publish Documentation

**What:** Publish project documentation with GitHub Pages.

**Why:** The rubric checks Pages, documented URLs, and structured explanation.

**Who:** GitHub Actions Pages workflow.

**Where:** `docs/` and `.github/workflows/pages.yml`.

**When:** After docs are updated and pushed to `main`.

**How:**

```bash
git add README.md docs/
git commit -m "Update project documentation"
git push
```

Verify:

```bash
gh run list --repo mhadiyahya/devops-bootcamp-project --workflow pages.yml --limit 3
curl -I https://hadiyahyalab.com
```

## 11. CI/CD And PR Gate

**What:** Confirm GitHub Actions workflows are present and branch protection requires Terraform.

**Why:** This supports the CI/CD and PR gate bonus marks.

**Who:** GitHub Actions and branch protection.

**Where:** `.github/workflows/`.

**When:** Before final submission.

**How:**

```bash
gh run list --repo mhadiyahya/devops-bootcamp-project --limit 10
gh api repos/mhadiyahya/devops-bootcamp-project/branches/main/protection
```

Expected:

- `Terraform Plan` workflow succeeds
- `Build And Push App Image` workflow succeeds
- `Publish Documentation` workflow succeeds
- `main` requires the `terraform` status check

## 12. Evidence To Capture

**What:** Screenshots and outputs for submission.

**Why:** Marks are easier to defend when evidence is visible.

**Who:** You.

**Where:** AWS Console, GitHub, Cloudflare, Grafana, browser.

**When:** After all services are green.

**How:** Capture these:

- Preflight script passing
- Terraform outputs
- Backend S3 bucket and DynamoDB lock table
- VPC, subnets, route tables, Internet Gateway
- Private route through web NAT instance
- Only one Elastic IP attached to web
- EC2 instances with expected private IPs
- SSM managed instances online
- ECR image with `latest`
- Web app at `web.hadiyahyalab.com`
- Cloudflare DNS A record for web
- Cloudflare Tunnel for monitoring
- Prometheus targets up
- Grafana dashboard with server filter
- GitHub Actions successful runs
- Branch protection requiring `terraform`
- GitHub Pages at `hadiyahyalab.com`

## 13. Final Smoke Test

Run these before presenting:

```bash
terraform -chdir=terraform/envs/prod fmt -check
terraform -chdir=terraform/envs/prod validate
cd terraform/envs/prod && terraform plan -detailed-exitcode
```

```bash
curl -I http://web.hadiyahyalab.com
curl -I https://monitoring.hadiyahyalab.com
curl -I https://hadiyahyalab.com
```

```bash
./scripts/ssm-run.sh <monitoring-instance-id> \
  "curl -sf 'http://localhost:9090/api/v1/query?query=up'"
```

Expected:

- Terraform plan shows no changes
- Web returns `200`
- Monitoring returns Grafana login redirect
- Pages returns `200`
- Prometheus target values are `1`

## 14. Cleanup After Assessment

For the full cleanup procedure, including ECR image deletion and backend bucket cleanup, read [`destroy-aws-resources.md`](destroy-aws-resources.md).

**What:** Destroy resources to avoid cost.

**Why:** EC2, EIP, S3, and other AWS resources can continue billing.

**Who:** You.

**Where:** Terraform folders.

**When:** Only after the assessment is complete.

**How:**

```bash
cd terraform/envs/prod
terraform destroy

cd ../bootstrap
terraform destroy
```

Do not destroy before all screenshots and grading checks are complete.
