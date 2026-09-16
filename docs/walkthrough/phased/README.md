# Phased Walkthrough

This folder splits the project into two learning phases.

Use this when you want to understand the thinking process first, then build the project step by step with commented code and commands.

## Phase 1: Strategy, Design, And Assessment Thinking

Read first:

```text
phase-1-strategy.md
```

This explains:

- what the project is trying to prove
- how the scoring rubric maps to technical choices
- why the architecture uses public/private subnets
- why SSM is used instead of SSH
- why the project uses one Elastic IP
- how to think about Terraform, Ansible, Docker, monitoring, and CI/CD before writing code

## Phase 2: Implementation, Code, And Verification

Read second:

```text
phase-2-implementation.md
```

This explains:

- folder creation
- preflight checks
- Terraform backend code
- production Terraform code
- Dockerfile code
- Ansible code
- GitHub Actions code
- Cloudflare setup
- Prometheus/Grafana verification
- final assessment checklist

## How To Use These Files

1. Read Phase 1 before touching AWS.
2. Build Phase 2 one section at a time.
3. After every major step, capture evidence.
4. If something breaks, compare the broken area with the related Phase 1 design decision.

The original shorter walkthrough remains at:

```text
docs/walkthrough/README.md
```

The full detailed walkthrough remains at:

```text
docs/walkthrough/detailed-build.md
```
