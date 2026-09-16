# DevOps Bootcamp Project

Full DevOps bootcamp final project for `hadiyahyalab.com`.

## Project Values

| Item | Value |
| --- | --- |
| AWS account | `713362557514` |
| AWS region | `ap-southeast-1` |
| Resource suffix | `hadiyahya` |
| Domain | `hadiyahyalab.com` |
| App URL | `http://web.hadiyahyalab.com` |
| Grafana URL | `https://monitoring.hadiyahyalab.com` |
| GitHub repo | `https://github.com/mhadiyahya/devops-bootcamp-project` |

## Architecture

The project provisions a single AWS VPC named `devops-vpc` with CIDR `10.0.0.0/24`.

| Server | Subnet | Private IP | Purpose |
| --- | --- | --- | --- |
| Web | Public `10.0.0.0/25` | `10.0.0.5` | Dockerized application and node_exporter |
| Controller | Private `10.0.0.128/25` | `10.0.0.135` | Runs Ansible configuration |
| Monitoring | Private `10.0.0.128/25` | `10.0.0.136` | Prometheus and Grafana |

Access is SSM-first. Private instances do not require inbound SSH. To keep the project to one Elastic IP, the web server also acts as the NAT instance for private outbound traffic.

## 1. Preflight

Run this before provisioning anything:

```bash
./scripts/preflight-check.sh
```

After EC2 instances exist, test SSM connectivity:

```bash
./scripts/preflight-check.sh --name-tag devops-web-server
./scripts/preflight-check.sh --name-tag devops-ansible-controller
./scripts/preflight-check.sh --name-tag devops-monitoring-server
```

Run ad hoc SSM checks:

```bash
./scripts/ssm-run.sh <instance-id> "docker ps"
```

## 2. Bootstrap Terraform State

Create the remote state bucket and lock table:

```bash
cd terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply
```

This creates:

- S3 bucket `devops-bootcamp-terraform-hadiyahya`
- DynamoDB table `devops-bootcamp-terraform-lock-hadiyahya`

## 3. Provision AWS Infrastructure

```bash
cd terraform/envs/prod
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
```

Important outputs:

- `web_public_ip`
- `ecr_repository_url`
- `web_instance_id`
- `controller_instance_id`
- `monitoring_instance_id`
- `ansible_ssm_bucket`

## 4. Build And Push The App Image

The app source lives in `app/` and uses a multi-stage Dockerfile.

Local build:

```bash
cd app
docker build -t final-project-app .
```

Push through GitHub Actions:

1. Add repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
2. Run the `Build And Push App Image` workflow, or push to `main`.

The image is pushed to:

```text
devops-bootcamp/final-project-hadiyahya
```

## 5. Configure Servers With Ansible

The preferred path is the `Deploy With Ansible Controller` GitHub Actions workflow. It sends an SSM command to the private controller, then the controller runs Ansible against the web and monitoring instances through SSM.

Local trigger for the same controller-based flow:

```bash
./scripts/deploy-from-controller.sh
```

Manual controller run:

```bash
./scripts/render-ansible-vars.sh
cd ansible
ansible-galaxy install -r requirements.yml
ansible-inventory --graph
ansible-playbook playbooks/site.yml
```

Ansible installs Docker, runs the application container on the web server, runs node_exporter on the web server, and runs Prometheus/Grafana on the monitoring server.

## 6. Cloudflare Setup

Cloudflare is intentionally manual because tunnel tokens and zone settings are account-specific.

### Web App

Create an A record:

| Type | Name | Target |
| --- | --- | --- |
| `A` | `web` | Terraform output `web_public_ip` |

The app should load at:

```text
http://web.hadiyahyalab.com
```

### Grafana

Create a Cloudflare Tunnel route:

| Hostname | Private service |
| --- | --- |
| `monitoring.hadiyahyalab.com` | `http://10.0.0.136:3000` |

The monitoring EC2 instance must not expose Grafana publicly through an AWS security group.

## 7. GitHub Pages

The `Publish Documentation` workflow publishes `docs/` to GitHub Pages. The custom domain file is `docs/CNAME`.

Expected documentation URL:

```text
https://hadiyahyalab.com
```

The `main` branch is protected with the Terraform workflow required as the pull request plan gate.

## Evidence Checklist

Add screenshots before final submission:

- Preflight passing
- Terraform outputs
- VPC, subnets, route tables, web NAT instance route, Internet Gateway
- EC2 instances with expected private IPs
- SSM managed instances
- ECR image pushed
- App running at `web.hadiyahyalab.com`
- Prometheus target for `10.0.0.5:9100`
- Grafana dashboard with CPU, memory, and disk metrics
- Cloudflare DNS record for web
- Cloudflare Tunnel route for monitoring
- GitHub Pages documentation

## Cleanup

To avoid ongoing AWS cost after assessment:

```bash
cd terraform/envs/prod
terraform destroy

cd ../bootstrap
terraform destroy
```
