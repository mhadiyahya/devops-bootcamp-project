# Cloudflare Manual Setup

## Web Domain

Create a DNS record in the `hadiyahyalab.com` zone:

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| A | `web` | Terraform output `web_public_ip` | Optional |

Use `http://web.hadiyahyalab.com` for the project app.

## Monitoring Domain

Create a Cloudflare Tunnel and route:

| Public hostname | Service |
| --- | --- |
| `monitoring.hadiyahyalab.com` | `http://10.0.0.136:3000` |

The monitoring AWS security group must not allow public inbound traffic to Grafana.

## GitHub Pages Domain

The Pages workflow publishes `docs/` and includes `docs/CNAME` with:

```text
hadiyahyalab.com
```

If the root domain is used elsewhere, change `docs/CNAME` and the Pages custom domain to a documentation subdomain such as `docs.hadiyahyalab.com`.
