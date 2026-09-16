#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/envs/prod"
OUT_DIR="$ROOT_DIR/ansible/group_vars/all"
OUT_FILE="$OUT_DIR/terraform_outputs.yml"

cd "$TF_DIR"

ECR_REPOSITORY_URL="$(terraform output -raw ecr_repository_url)"
ANSIBLE_SSM_BUCKET="$(terraform output -raw ansible_ssm_bucket)"

mkdir -p "$OUT_DIR"

cat >"$OUT_FILE" <<EOF
---
ecr_repository_url: "$ECR_REPOSITORY_URL"
ansible_ssm_bucket: "$ANSIBLE_SSM_BUCKET"
EOF

echo "Wrote $OUT_FILE"
