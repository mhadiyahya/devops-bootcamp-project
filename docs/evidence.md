# Evidence Checklist

Capture screenshots for these items before submission:

- `scripts/preflight-check.sh` passing
- Terraform backend bucket and lock table
- Terraform production outputs
- VPC `devops-vpc`
- Public and private subnets
- Internet Gateway and NAT Gateway
- Public and private route tables
- EC2 instances:
  - `devops-web-server`
  - `devops-ansible-controller`
  - `devops-monitoring-server`
- EC2 private IPs:
  - `10.0.0.5`
  - `10.0.0.135`
  - `10.0.0.136`
- SSM managed instance status for all three servers
- ECR repository and pushed image
- App page at `web.hadiyahyalab.com`
- node_exporter target in Prometheus
- Grafana dashboard
- Cloudflare DNS for `web.hadiyahyalab.com`
- Cloudflare Tunnel for `monitoring.hadiyahyalab.com`
- GitHub Pages documentation
