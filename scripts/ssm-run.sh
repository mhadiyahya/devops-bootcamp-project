#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <instance-id> <command...>" >&2
  exit 1
fi

INSTANCE_ID="$1"
shift
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
COMMAND="$*"

PARAM_FILE="$(mktemp)"
trap 'rm -f "$PARAM_FILE"' EXIT

python3 - "$COMMAND" "$PARAM_FILE" <<'PY'
import json
import sys

command = sys.argv[1]
path = sys.argv[2]

with open(path, "w", encoding="utf-8") as fh:
    json.dump({"commands": [command]}, fh)
PY

COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "file://$PARAM_FILE" \
  --query Command.CommandId \
  --output text)"

for _ in $(seq 1 120); do
  STATUS="$(aws ssm get-command-invocation \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query Status \
    --output text)"

  case "$STATUS" in
    Success|Cancelled|TimedOut|Failed|Cancelling)
      break
      ;;
  esac

  sleep 2
done

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' \
  --output text

[[ "${STATUS:-Unknown}" == "Success" ]]
