#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/envs/prod"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
APP_IMAGE_TAG="${APP_IMAGE_TAG:-latest}"
REPO_URL="${REPO_URL:-https://github.com/mhadiyahya/devops-bootcamp-project.git}"

cd "$TF_DIR"

CONTROLLER_INSTANCE_ID="$(terraform output -raw controller_instance_id)"
ECR_REPOSITORY_URL="$(terraform output -raw ecr_repository_url)"
ANSIBLE_SSM_BUCKET="$(terraform output -raw ansible_ssm_bucket)"

COMMAND_FILE="$(mktemp)"
trap 'rm -f "$COMMAND_FILE"' EXIT

cat >"$COMMAND_FILE" <<EOF
{
  "commands": [
    "set -euo pipefail",
    "if ! command -v ansible >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y git ansible python3-boto3 python3-botocore; fi",
    "sudo -u ubuntu bash -lc 'rm -rf ~/devops-bootcamp-project && git clone ${REPO_URL} ~/devops-bootcamp-project'",
    "sudo -u ubuntu bash -lc 'cd ~/devops-bootcamp-project && ansible-galaxy install -r ansible/requirements.yml'",
    "sudo -u ubuntu bash -lc 'mkdir -p ~/devops-bootcamp-project/ansible/group_vars/all'",
    "sudo -u ubuntu bash -lc 'cat > ~/devops-bootcamp-project/ansible/group_vars/all/terraform_outputs.yml <<VARS\n---\necr_repository_url: \"${ECR_REPOSITORY_URL}\"\nansible_ssm_bucket: \"${ANSIBLE_SSM_BUCKET}\"\napp_image_tag: \"${APP_IMAGE_TAG}\"\nVARS'",
    "sudo -u ubuntu bash -lc 'cd ~/devops-bootcamp-project/ansible && ansible-playbook playbooks/site.yml'"
  ]
}
EOF

COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$CONTROLLER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Deploy devops bootcamp app and monitoring from controller" \
  --parameters "file://$COMMAND_FILE" \
  --query Command.CommandId \
  --output text)"

echo "Sent command $COMMAND_ID to controller $CONTROLLER_INSTANCE_ID"

aws ssm wait command-executed \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$CONTROLLER_INSTANCE_ID"

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$CONTROLLER_INSTANCE_ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' \
  --output text
