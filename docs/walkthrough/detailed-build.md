# Detailed Build Walkthrough: From Empty Folder To Final Project

This guide explains how to build the project from start to finish, including the code structure, logic, fundamentals, and assessment checkpoints. Use this when you want to rebuild the project yourself, not only run the final commands.

The shorter A-Z checklist is in [`README.md`](README.md). This file is the deeper version.

## 1. Understand The Target Before Coding

### What You Are Building

You are building a small but complete DevOps platform:

- A public web application served from Docker on EC2.
- Infrastructure managed by Terraform.
- Configuration managed by Ansible.
- Container image stored in private Amazon ECR.
- Monitoring with Prometheus and Grafana.
- Public documentation through GitHub Pages.
- Access through AWS SSM instead of SSH.
- Public app DNS using `web.hadiyahyalab.com`.
- Private Grafana access using Cloudflare Tunnel at `monitoring.hadiyahyalab.com`.

### Why This Architecture

The assessment is not only checking whether the website loads. It checks whether you can connect these fundamentals:

- **Infrastructure as Code:** Terraform should describe AWS resources repeatably.
- **Networking:** Public and private subnet separation should be clear.
- **Security:** Private servers should not be exposed directly to the internet.
- **Automation:** Ansible and GitHub Actions should reduce manual server work.
- **Containers:** The app should be built once and deployed from a registry.
- **Observability:** Prometheus and Grafana should prove the servers are measurable.
- **Documentation:** A reviewer should understand and reproduce the project.

### Assessment Checkpoint

Before implementation, map every rubric item to an artifact:

| Rubric Area | Evidence Artifact |
| --- | --- |
| Terraform backend | `terraform/bootstrap/`, S3 bucket, lock table |
| VPC/network | `terraform/envs/prod/main.tf`, AWS VPC screenshots |
| Security groups | Terraform SG rules and AWS console |
| EC2 | Terraform instances and EC2 console |
| Ansible | `ansible/` roles and successful playbook run |
| Docker | `app/Dockerfile` |
| Container deployment | `docker ps` on web server |
| ECR | ECR image list |
| DNS | Cloudflare DNS and `curl` output |
| Tunnel | Cloudflare Tunnel status and Grafana URL |
| Monitoring | Prometheus targets and Grafana dashboard |
| GitHub Pages | Pages URL and workflow |
| CI/CD bonus | GitHub Actions runs |

## 2. Start With Repository Structure

### What To Create

Use folders that reflect ownership:

```text
devops-bootcamp-project/
  app/
  ansible/
  docs/
  scripts/
  terraform/
    bootstrap/
    envs/
      prod/
  .github/
    workflows/
```

### Why This Structure

Each folder has a single responsibility:

- `app/` owns application build logic.
- `terraform/` owns cloud resources.
- `ansible/` owns server configuration.
- `scripts/` owns operator commands.
- `.github/workflows/` owns CI/CD.
- `docs/` owns assessment explanation.

This matters for assessment because a reviewer can quickly find evidence without guessing.

### How To Begin

```bash
mkdir -p app ansible docs scripts terraform/bootstrap terraform/envs/prod .github/workflows
git init
```

Then add a `README.md` early. Even a simple README helps you keep the project direction clear.

## 3. Build The Preflight Script First

### What The Script Does

`scripts/preflight-check.sh` checks:

- Git is installed.
- GitHub CLI is authenticated.
- GitHub repo can be reached.
- AWS CLI exists.
- Session Manager plugin exists.
- AWS region/profile are visible.
- AWS identity works.
- Optional SSM command can run on an EC2 instance.

### Why It Comes First

Preflight reduces confusion. If AWS credentials or GitHub authentication fail, Terraform and CI/CD failures become noisy and misleading.

### Logic To Understand

The script should not stop at the first failure. It should:

1. Run each check.
2. Track pass/fail status.
3. Print a summary.
4. Exit with meaningful codes.

Good operational scripts are diagnostic, not mysterious.

### Assessment Checkpoint

Screenshot:

```bash
./scripts/preflight-check.sh
```

Expected:

```text
PASS: Preflight passed
```

## 4. Bootstrap Terraform Backend

### What The Backend Is

Terraform state records what Terraform created. For team-style or assessment-style work, local state is weaker evidence than remote state.

`terraform/bootstrap/` creates:

- S3 bucket for state.
- DynamoDB table for state locking.
- Bucket encryption and public access block.

### Why Separate Bootstrap From Prod

Terraform cannot use an S3 backend until the S3 bucket exists. So you create the backend first with a local state, then use that backend in production Terraform.

### Code Logic

In `terraform/bootstrap/main.tf`:

- `aws_s3_bucket` creates the state bucket.
- `aws_s3_bucket_versioning` protects history.
- `aws_s3_bucket_server_side_encryption_configuration` encrypts state.
- `aws_s3_bucket_public_access_block` prevents accidental public state.
- `aws_dynamodb_table` provides locking.

### Commands

```bash
cd terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply
terraform output
```

### Assessment Checkpoint

Evidence:

- S3 bucket `devops-bootcamp-terraform-hadiyahya`.
- DynamoDB table `devops-bootcamp-terraform-lock-hadiyahya`.
- Terraform output screenshot.

## 5. Design The AWS Network

### What The Network Contains

Production Terraform creates:

- VPC `10.0.0.0/24`.
- Public subnet `10.0.0.0/25`.
- Private subnet `10.0.0.128/25`.
- Internet Gateway.
- Public route table to the Internet Gateway.
- Private route table through the web instance as NAT.

### Why Public And Private Subnets

The web server must be reachable by users, so it sits in the public subnet.

The controller and monitoring servers do not need public inbound access, so they sit in the private subnet.

This is a core cloud networking pattern:

```text
Internet -> web server
private servers -> outbound through NAT path
internet -> no direct access to private servers
```

### Why Web NAT Instance Instead Of NAT Gateway

The assessment only needs one Elastic IP. An AWS managed NAT Gateway requires its own Elastic IP, which would create a second EIP.

To keep one EIP:

- The web instance keeps the only Elastic IP.
- Source/destination check is disabled on the web instance.
- Linux IP forwarding is enabled.
- An iptables masquerade rule translates private subnet traffic.
- The private route table sends `0.0.0.0/0` to the web instance network interface.

Tradeoff:

- Lower cost and one EIP.
- Private outbound depends on the web instance being healthy.

### Code Logic

In `terraform/envs/prod/main.tf`:

- `aws_vpc.main` defines the network boundary.
- `aws_subnet.public` and `aws_subnet.private` split placement.
- `aws_route_table.public` sends internet traffic to the IGW.
- `aws_route_table.private` sends outbound internet through the web instance ENI.
- `source_dest_check = false` allows the web instance to forward traffic.
- `web_user_data` configures Linux NAT and a systemd service.

### Assessment Checkpoint

Run:

```bash
aws ec2 describe-addresses --region ap-southeast-1 --output table
aws ec2 describe-route-tables --region ap-southeast-1 --output table
```

Evidence should show:

- Only one Elastic IP.
- Public route to IGW.
- Private route to web instance ENI.

## 6. Design Security Groups

### What To Allow

Public web security group:

- Inbound HTTP `80` from internet.
- Inbound node_exporter `9100` from private security group.
- Inbound private subnet traffic for NAT forwarding.
- Outbound all.

Private security group:

- Inbound only from itself for private east-west traffic.
- Outbound all through the private route table.

### Why No SSH

The project uses SSM Session Manager and SSM Run Command. That means:

- No port `22` is required.
- Private servers can stay private.
- Access is controlled by IAM.

### Assessment Checkpoint

In AWS console or CLI, prove:

- Monitoring has no public IP.
- Controller has no public IP.
- Private security group has no public `0.0.0.0/0` inbound.
- Web only exposes required public HTTP.

## 7. Design IAM Roles

### What Roles Exist

Each server has its own IAM role:

- Web role.
- Controller role.
- Monitoring role.

All get `AmazonSSMManagedInstanceCore` so they can register with SSM.

Additional policies:

- Web can pull the application image from ECR.
- Controller can pull ECR and send SSM commands for Ansible-style operations.

### Why Separate Roles

Separate roles support least privilege. If one instance is compromised, it should not automatically have every permission used by every other instance.

### Code Logic

The ECR policy is split because AWS requires:

- `ecr:GetAuthorizationToken` on `*`.
- Image read actions scoped to the project repository ARN.

The controller SSM policy is split because:

- Discovery actions often require `*`.
- Command/session actions can be scoped more tightly.
- S3 access is scoped to the Ansible SSM bucket.

### Assessment Checkpoint

Evidence:

- Three instance profiles in EC2.
- Separate IAM roles.
- Custom project policies scoped to project resources where AWS supports it.

## 8. Create EC2 Instances

### What Instances To Build

| Role | Private IP | Subnet | Purpose |
| --- | --- | --- | --- |
| Web | `10.0.0.5` | Public | App container, node_exporter, NAT instance |
| Controller | `10.0.0.135` | Private | Runs Ansible |
| Monitoring | `10.0.0.136` | Private | Prometheus, Grafana, Cloudflare Tunnel |

### Why Static Private IPs

Static private IPs make Prometheus and documentation simple. For example, Prometheus can scrape:

```text
10.0.0.5:9100
10.0.0.135:9100
```

### User Data Logic

Common user data:

- Installs packages needed by later automation.
- Installs and starts SSM agent.

Controller user data:

- Installs Ansible.
- Installs Session Manager plugin.
- Installs Ansible collections and roles.

Web user data:

- Enables IP forwarding.
- Adds NAT masquerade.
- Installs a systemd service so NAT returns after reboot.

### Assessment Checkpoint

Run:

```bash
aws ssm describe-instance-information --region ap-southeast-1 --output table
```

All three instances should be `Online`.

## 9. Build The Application Container

### What The Dockerfile Does

The Dockerfile is multi-stage:

1. Build stage uses Node.
2. Runs `npm ci`.
3. Runs tests and build.
4. Runtime stage uses Nginx.
5. Copies built static files into Nginx.
6. Adds a container healthcheck.

### Why Multi-Stage

Multi-stage builds keep the final image smaller and cleaner. Build tools stay in the build layer; runtime only needs Nginx and static files.

### Code Logic

Important lines:

```dockerfile
FROM node:22-alpine AS build
RUN npm ci
RUN npm test && npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

This proves:

- Dependencies are installed reproducibly.
- Tests run during build.
- Runtime image is not the same as build image.

### Assessment Checkpoint

Build locally:

```bash
cd app
docker build -t final-project-app .
```

Then verify ECR push through GitHub Actions:

```bash
aws ecr describe-images \
  --region ap-southeast-1 \
  --repository-name devops-bootcamp/final-project-hadiyahya \
  --output table
```

## 10. Use GitHub Actions For Image Build

### What The Workflow Does

`.github/workflows/docker-image.yml`:

- Runs on push to `main` when `app/**` changes.
- Authenticates to AWS.
- Logs in to ECR.
- Builds the Docker image.
- Pushes both commit SHA and `latest` tags.

### Why Tag With SHA And Latest

- SHA tag is immutable evidence of exactly what code was built.
- `latest` is convenient for deployment.

### Assessment Checkpoint

Evidence:

- Successful `Build And Push App Image` run.
- ECR image with `latest`.

## 11. Configure Ansible

### What Ansible Owns

Ansible handles server state:

- Docker installation.
- Web app container.
- node_exporter.
- Prometheus.
- Grafana.
- Grafana datasource.
- Grafana dashboard.

Terraform creates the servers. Ansible configures inside the servers.

### Why This Split Matters

Terraform is best for infrastructure lifecycle:

```text
create VPC, EC2, IAM, ECR
```

Ansible is best for OS/application state:

```text
install Docker, run containers, render config files
```

### Inventory Logic

The AWS EC2 dynamic inventory groups instances by tags:

- `role_web`
- `role_controller`
- `role_monitoring`

This means Ansible targets roles, not hardcoded instance IDs.

### Playbook Logic

`ansible/playbooks/site.yml` has three plays:

- Configure web server.
- Configure controller metrics.
- Configure monitoring server.

This makes the responsibility clear and easy to assess.

### Idempotency Logic

Ansible tasks use modules such as:

- `ansible.builtin.file`
- `ansible.builtin.template`
- `community.docker.docker_container`
- `community.docker.docker_compose_v2`

These modules understand desired state. Running the playbook twice should not recreate everything unnecessarily.

### Assessment Checkpoint

Run deployment twice:

```bash
./scripts/deploy-from-controller.sh
./scripts/deploy-from-controller.sh
```

The second run should show minimal changes.

## 12. Deploy From The Controller Through SSM

### What Happens

The deploy script/workflow sends an SSM command to the private controller. The controller then:

1. Clones the repo.
2. Installs Ansible requirements.
3. Renders Terraform outputs as Ansible variables.
4. Runs the playbook.

### Why This Is Stronger Than Laptop-Only Ansible

It proves the controller server has a real role in the architecture. It also avoids exposing SSH and keeps administration inside AWS private networking.

### Assessment Checkpoint

Evidence:

- Controller is private.
- Controller is SSM online.
- Deploy workflow sends SSM command.
- App and monitoring services update after the workflow.

## 13. Configure Prometheus

### What Prometheus Scrapes

Prometheus runs on monitoring and scrapes:

```text
localhost:9090
10.0.0.5:9100
10.0.0.135:9100
```

The `server` label separates:

- `web`
- `controller`

### Why Labels Matter

Without labels, Grafana can show metrics but filtering is harder. Labels make dashboard variables possible.

Example idea:

```yaml
- targets:
    - 10.0.0.5:9100
  labels:
    server: web
```

### Assessment Checkpoint

Run:

```bash
./scripts/ssm-run.sh <monitoring-instance-id> \
  "curl -sf 'http://localhost:9090/api/v1/query?query=up'"
```

All target values should be `1`.

## 14. Configure Grafana

### What Grafana Needs

Grafana needs:

- Prometheus datasource.
- Dashboard provider.
- Dashboard JSON.

### Why Provisioning Is Better Than Manual Dashboard Clicks

Provisioning keeps the dashboard as code. If the monitoring instance is rebuilt, Ansible restores the same dashboard automatically.

### Dashboard Logic

The dashboard includes:

- Server filter variable.
- CPU panels.
- Memory panels.
- Disk panels.
- Network panels.
- Uptime/load panels.
- Exporter health.

The important assessment point is not only that Grafana opens, but that it shows meaningful telemetry for web and controller.

### Assessment Checkpoint

Open:

```text
https://monitoring.hadiyahyalab.com
```

Then verify:

```text
Dashboards -> DevOps Bootcamp -> Bootcamp Nodes - Web and Controller
```

Use the server filter to switch between `web`, `controller`, and `All`.

## 15. Configure Cloudflare

### Web DNS

Create:

| Type | Name | Target |
| --- | --- | --- |
| `A` | `web` | web Elastic IP |

Why:

- The rubric checks DNS record to the Elastic IP.
- The app should have a friendly URL.

Verify:

```bash
curl -I http://web.hadiyahyalab.com
```

Expected:

```text
HTTP/1.1 200 OK
```

### Monitoring Tunnel

Create a Cloudflare Tunnel to the monitoring instance.

Why:

- Grafana is reachable by hostname.
- Monitoring server does not need public inbound ports.

Verify:

```bash
curl -I https://monitoring.hadiyahyalab.com
```

Expected:

```text
HTTP/2 302
```

The `302` means Grafana is reachable and redirecting to login.

## 16. Configure GitHub Pages

### What Pages Publishes

The Pages workflow publishes:

- `docs/index.html`
- `docs/cloudflare.md`
- `docs/evidence.md`
- `docs/walkthrough/`
- `README.md` copy

### Why Pages Matters

The assessment asks for published documentation and URL evidence.

### Custom Domain Logic

`docs/CNAME` contains:

```text
hadiyahyalab.com
```

This tells GitHub Pages which custom domain to use.

### Remaining One-Point Remark

GitHub Pages HTTPS enforcement is not enabled yet because GitHub has not issued the certificate. This is why the score estimate is `121/122`, not `122/122`.

The site is still accessible through Cloudflare HTTPS:

```text
https://hadiyahyalab.com
```

Later, recheck GitHub:

```bash
gh api repos/mhadiyahya/devops-bootcamp-project/pages
```

When GitHub is ready, enable Enforce HTTPS in repository Pages settings.

## 17. Configure CI/CD And PR Gate

### Workflows

| Workflow | Purpose |
| --- | --- |
| `terraform-plan.yml` | PR/manual Terraform fmt, init, validate, plan |
| `docker-image.yml` | Build and push app image to ECR |
| `deploy.yml` | Deploy from controller through SSM |
| `pages.yml` | Publish documentation |

### Branch Protection

The `main` branch requires the `terraform` status check. This proves a Terraform plan gate exists for PRs.

### Assessment Checkpoint

Run:

```bash
gh run list --repo mhadiyahya/devops-bootcamp-project --limit 10
gh api repos/mhadiyahya/devops-bootcamp-project/branches/main/protection
```

Look for:

- `Terraform Plan` success.
- Required status check `terraform`.

## 18. Final Assessment Flow

When presenting, use this order:

1. Show public GitHub repo.
2. Show `README.md` and walkthrough docs.
3. Show Terraform backend resources.
4. Show Terraform production resources.
5. Show one Elastic IP only.
6. Show VPC/subnets/routes.
7. Show EC2 private/public placement.
8. Show security groups.
9. Show SSM managed instances.
10. Show ECR image.
11. Show app URL.
12. Show Cloudflare DNS.
13. Show Cloudflare Tunnel.
14. Show monitoring server has no public access.
15. Show Prometheus targets up.
16. Show Grafana dashboard and filter.
17. Show GitHub Actions.
18. Show GitHub Pages.
19. Mention the one-point HTTPS enforcement remark.

## 19. Final Smoke Test Commands

Run these before assessment:

```bash
./scripts/preflight-check.sh
```

```bash
terraform -chdir=terraform/envs/prod fmt -check
terraform -chdir=terraform/envs/prod validate
cd terraform/envs/prod && terraform plan -detailed-exitcode
```

```bash
aws ec2 describe-addresses --region ap-southeast-1 --output table
aws ssm describe-instance-information --region ap-southeast-1 --output table
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

- Preflight passes.
- Terraform plan has no changes.
- One Elastic IP exists.
- All three instances are SSM online.
- Web returns `200`.
- Monitoring returns Grafana login redirect.
- Pages returns `200`.
- Prometheus targets are up.

## 20. Common Failure Patterns

### AWS Credentials Fail

Symptom:

```text
InvalidClientTokenId
```

Fix:

```bash
aws configure
aws sts get-caller-identity
```

### SSM Instance Missing

Possible causes:

- IAM role missing `AmazonSSMManagedInstanceCore`.
- SSM agent not running.
- Private instance has no outbound path.
- NAT route is broken.

Check:

```bash
aws ssm describe-instance-information --region ap-southeast-1
```

### Private Instance Cannot Reach Internet

Possible causes:

- Web NAT service stopped.
- Web source/destination check enabled.
- Private route does not point to web ENI.

Check web:

```bash
./scripts/ssm-run.sh <web-instance-id> \
  "systemctl is-active devops-nat.service; cat /proc/sys/net/ipv4/ip_forward; sudo iptables -t nat -S POSTROUTING"
```

### Prometheus Target Down

Possible causes:

- node_exporter container stopped.
- Security group blocks port `9100`.
- Prometheus config has wrong IP or label.

Check:

```bash
./scripts/ssm-run.sh <web-instance-id> "docker ps"
./scripts/ssm-run.sh <controller-instance-id> "docker ps"
```

### Grafana Has No Dashboard

Possible causes:

- Grafana provisioning files not rendered.
- Monitoring stack not restarted.
- Docker Compose failed.

Check:

```bash
./scripts/ssm-run.sh <monitoring-instance-id> \
  "ls -R /opt/grafana /opt/prometheus && docker ps"
```

## 21. Cleanup

Only clean up after assessment.

```bash
cd terraform/envs/prod
terraform destroy

cd ../bootstrap
terraform destroy
```

Remember: screenshots and evidence should be captured before destroying anything.
