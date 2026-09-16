# Phase 1: Strategy, Design, And Assessment Thinking

This phase is about how to think before building. The goal is to understand the architecture, the tradeoffs, and the scoring logic so the implementation feels intentional instead of like a list of random commands.

## 1. Start From The Rubric

The project should be designed from the assessment backward.

The rubric asks for:

- Terraform backend
- VPC networking
- security groups
- EC2 servers
- Ansible
- Docker
- app container deployment
- idempotency
- ECR image push
- DNS to web Elastic IP
- Cloudflare Tunnel
- private monitoring server
- metrics from web server
- Prometheus
- Grafana dashboard
- GitHub Pages
- documented URLs
- structured explanation
- bonus CI/CD, IAM, PR gate, and no-SSH Ansible

The strategy is simple:

```text
Every score item must map to one visible artifact.
```

Examples:

| Rubric Item | Artifact To Show |
| --- | --- |
| Terraform backend | S3 bucket and DynamoDB lock table |
| VPC | Terraform code plus AWS VPC screenshot |
| Security group | Terraform SG code plus AWS SG screenshot |
| EC2 | Three running instances with expected IPs |
| Ansible | Playbook and successful deployment run |
| Docker | Multi-stage Dockerfile |
| ECR | Private repository with image tags |
| DNS | Cloudflare record and working web URL |
| Tunnel | Cloudflare Tunnel and Grafana URL |
| Monitoring | Prometheus targets and Grafana dashboard |
| CI/CD | GitHub Actions runs |
| PR gate | Branch protection requiring Terraform check |

## 2. Decide The Architecture

The architecture is:

```text
Internet
  |
  v
Cloudflare DNS
  |
  v
web.hadiyahyalab.com
  |
  v
Web EC2 in public subnet
  - Docker app on port 80
  - node_exporter on port 9100
  - NAT instance for private subnet

Private subnet
  - Controller EC2 at 10.0.0.135
  - Monitoring EC2 at 10.0.0.136

Cloudflare Tunnel
  |
  v
monitoring.hadiyahyalab.com -> Grafana on monitoring server
```

### Why This Design

**Public web server:** The app must be reachable by users and DNS must point to an Elastic IP.

**Private controller:** Ansible should run from inside AWS without public SSH.

**Private monitoring:** Grafana should be reachable through Cloudflare Tunnel, not a public AWS port.

**One Elastic IP:** The project only needs one EIP. A managed NAT Gateway requires another EIP, so the web server also acts as the NAT instance.

## 3. Think About Networking First

Networking decides whether everything else can work.

The VPC plan:

```text
VPC:            10.0.0.0/24
Public subnet:  10.0.0.0/25
Private subnet: 10.0.0.128/25
```

Important IPs:

```text
Web:        10.0.0.5
Controller: 10.0.0.135
Monitoring: 10.0.0.136
```

### Why Static Private IPs

Static IPs make the monitoring config easier:

```yaml
# Prometheus can scrape fixed targets.
- targets:
    - "10.0.0.5:9100"
  labels:
    server: web

- targets:
    - "10.0.0.135:9100"
  labels:
    server: controller
```

If IPs changed dynamically, Prometheus config and documentation would become harder to follow.

## 4. Think About Access

The project should avoid SSH.

Instead:

```text
Laptop -> AWS SSM -> EC2 instance
GitHub Actions -> AWS SSM -> Controller -> Ansible -> EC2 instances
```

### Why SSM

SSM gives:

- no port 22 exposure
- IAM-controlled access
- command execution on private instances
- better assessment evidence for security

Design rule:

```text
If you feel tempted to open SSH, check whether SSM can do it instead.
```

## 5. Think About Terraform Responsibilities

Terraform should own cloud infrastructure:

- backend resources
- VPC
- subnets
- routes
- Internet Gateway
- Elastic IP
- EC2
- ECR
- IAM roles
- security groups
- outputs

Terraform should not usually own:

- container runtime state
- Prometheus config files
- Grafana dashboards
- application process management

Those are better handled by Ansible.

### Terraform Strategy

Use two Terraform areas:

```text
terraform/bootstrap/
terraform/envs/prod/
```

Reason:

- `bootstrap` creates the remote state bucket and lock table.
- `prod` uses that backend to create the project infrastructure.

## 6. Think About Ansible Responsibilities

Ansible should own server configuration:

- install Docker
- log in to ECR
- run app container
- run node_exporter
- render Prometheus config
- render Grafana datasource
- render Grafana dashboard
- start monitoring stack

Design rule:

```text
Terraform creates servers. Ansible configures servers.
```

This separation makes the project easier to explain.

## 7. Think About Docker

The app should be built as an image and deployed as a container.

Strategy:

```text
source code -> Docker build -> private ECR -> web server pulls image -> container runs on port 80
```

Use a multi-stage Dockerfile:

- Node builds and tests the app.
- Nginx serves the built static files.

Why:

- cleaner runtime image
- smaller attack surface
- easy redeployment

## 8. Think About Monitoring

Monitoring has two layers:

```text
node_exporter -> Prometheus -> Grafana
```

What each part does:

| Tool | Role |
| --- | --- |
| node_exporter | Exposes Linux host metrics |
| Prometheus | Scrapes and stores metrics |
| Grafana | Visualizes metrics |

The dashboard should not only show one server. It should support:

- web
- controller
- all servers

That is why Prometheus labels matter:

```yaml
labels:
  server: web
```

Grafana can then filter by `server`.

## 9. Think About CI/CD

CI/CD should prove automation:

| Workflow | Purpose |
| --- | --- |
| Terraform Plan | PR gate and format validation |
| Build And Push App Image | Build Docker image and push to ECR |
| Deploy With Ansible Controller | Deploy through SSM and private controller |
| Publish Documentation | Publish GitHub Pages |

Strategy:

```text
Do manual commands first so you understand them.
Then automate them in GitHub Actions.
```

## 10. Think About Evidence While Building

Do not wait until the end to collect evidence. Capture after every milestone.

Good evidence moments:

- preflight passes
- Terraform backend applied
- Terraform prod outputs
- EC2 instances running
- SSM instances online
- one EIP only
- ECR image exists
- app URL works
- Cloudflare DNS works
- tunnel works
- Prometheus targets up
- Grafana dashboard works
- GitHub Actions successful
- Pages published

## 11. Risk And Tradeoff Notes

### One EIP NAT Tradeoff

Using the web server as NAT gives:

- one EIP
- lower cost
- simpler scoring against the one-EIP requirement

But it also means:

- private outbound depends on the web server
- web reboot can briefly affect private internet access

Mitigation:

- `devops-nat.service` restores NAT on boot
- SSM smoke tests verify private outbound

### GitHub Pages HTTPS Remark

The project reaches `121/122` because GitHub Pages HTTPS enforcement is waiting for GitHub certificate issuance.

Important wording:

```text
The site works through Cloudflare HTTPS, but GitHub Pages API still reports https_enforced=false until GitHub issues the custom-domain certificate.
```

This is an external readiness issue, not a missing implementation step.

## 12. Phase 1 Exit Checklist

Before moving to implementation, you should be able to explain:

- why there are three EC2 instances
- why controller and monitoring are private
- why SSM replaces SSH
- why only one Elastic IP exists
- why the web server acts as NAT
- what Terraform owns
- what Ansible owns
- how Docker image reaches the web server
- how Prometheus gets metrics
- how Grafana gets dashboards
- what each GitHub Actions workflow proves
- what evidence maps to each rubric item
