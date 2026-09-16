#!/usr/bin/env bash

set -u

DEFAULT_REGION="ap-southeast-1"
SHIP_REPO_URL="https://github.com/Infratify/ship.git"

REGION=""
PROFILE=""
INSTANCE_ID=""
NAME_TAG=""

TOOLING_FAILED=0
AWS_IDENTITY_FAILED=0
SSM_FAILED=0
AWS_IDENTITY_OK=0
CHECKS_TOTAL=0
CHECKS_FAILED=0

AWS_ACCOUNT=""
AWS_ARN=""
AWS_USER_ID=""
RESOLVED_REGION=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/preflight-check.sh [options]

Options:
  --region <region>         AWS region to use. Defaults to AWS CLI config, then ap-southeast-1.
  --profile <profile>       AWS profile to use.
  --instance-id <id>        EC2 instance ID to test through SSM.
  --name-tag <value>        Resolve one EC2 instance by tag:Name, then test it through SSM.
  -h, --help                Show this help.

Examples:
  ./scripts/preflight-check.sh
  ./scripts/preflight-check.sh --instance-id i-0123456789abcdef0
  ./scripts/preflight-check.sh --name-tag devops-web-server --region ap-southeast-1
USAGE
}

section() {
  printf '\n== %s ==\n' "$1"
}

info() {
  printf 'INFO: %s\n' "$1"
}

pass() {
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  printf 'FAIL: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
}

mark_tooling_failure() {
  TOOLING_FAILED=1
}

mark_aws_identity_failure() {
  AWS_IDENTITY_FAILED=1
}

mark_ssm_failure() {
  SSM_FAILED=1
}

require_command() {
  local command_name="$1"
  local label="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$label is installed: $(command -v "$command_name")"
    return 0
  fi

  fail "$label is not installed or is not on PATH"
  mark_tooling_failure
  return 1
}

run_capture() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>&1
}

run_aws_capture() {
  local output_file="$1"
  shift

  local aws_extra_args=()
  if [[ -n "$PROFILE" ]]; then
    aws_extra_args+=(--profile "$PROFILE")
  fi
  if [[ -n "$RESOLVED_REGION" ]]; then
    aws_extra_args+=(--region "$RESOLVED_REGION")
  fi

  aws "${aws_extra_args[@]}" "$@" >"$output_file" 2>&1
}

run_aws_text() {
  local aws_extra_args=()
  if [[ -n "$PROFILE" ]]; then
    aws_extra_args+=(--profile "$PROFILE")
  fi
  if [[ -n "$RESOLVED_REGION" ]]; then
    aws_extra_args+=(--region "$RESOLVED_REGION")
  fi

  aws "${aws_extra_args[@]}" "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --region)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          printf 'ERROR: --region requires a value\n' >&2
          usage
          exit 1
        fi
        REGION="$2"
        shift 2
        ;;
      --profile)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          printf 'ERROR: --profile requires a value\n' >&2
          usage
          exit 1
        fi
        PROFILE="$2"
        shift 2
        ;;
      --instance-id)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          printf 'ERROR: --instance-id requires a value\n' >&2
          usage
          exit 1
        fi
        INSTANCE_ID="$2"
        shift 2
        ;;
      --name-tag)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          printf 'ERROR: --name-tag requires a value\n' >&2
          usage
          exit 1
        fi
        NAME_TAG="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'ERROR: Unknown option: %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -n "$INSTANCE_ID" && -n "$NAME_TAG" ]]; then
    printf 'ERROR: Use either --instance-id or --name-tag, not both.\n' >&2
    usage
    exit 1
  fi
}

resolve_region() {
  if [[ -n "$REGION" ]]; then
    RESOLVED_REGION="$REGION"
    return
  fi

  local aws_extra_args=()
  if [[ -n "$PROFILE" ]]; then
    aws_extra_args+=(--profile "$PROFILE")
  fi

  RESOLVED_REGION="$(aws "${aws_extra_args[@]}" configure get region 2>/dev/null || true)"
  if [[ -z "$RESOLVED_REGION" ]]; then
    RESOLVED_REGION="$DEFAULT_REGION"
  fi
}

check_github() {
  section "GitHub"

  if require_command git "git"; then
    local git_version
    git_version="$(git --version 2>&1)"
    pass "$git_version"

    local ls_remote_output
    ls_remote_output="$(mktemp)"
    if run_capture "$ls_remote_output" git ls-remote "$SHIP_REPO_URL" HEAD; then
      pass "Laptop can query $SHIP_REPO_URL"
      sed 's/^/      /' "$ls_remote_output"
    else
      fail "Laptop cannot query $SHIP_REPO_URL"
      sed 's/^/      /' "$ls_remote_output"
      mark_tooling_failure
    fi
    rm -f "$ls_remote_output"
  fi

  if require_command gh "GitHub CLI"; then
    local gh_output
    gh_output="$(mktemp)"
    if run_capture "$gh_output" gh auth status; then
      pass "GitHub CLI is authenticated"
    else
      fail "GitHub CLI authentication failed"
      mark_tooling_failure
    fi
    sed 's/^/      /' "$gh_output"
    rm -f "$gh_output"
  fi
}

check_aws_cli() {
  section "AWS CLI"

  if require_command aws "AWS CLI"; then
    local aws_version
    aws_version="$(aws --version 2>&1)"
    pass "$aws_version"
  fi

  if require_command session-manager-plugin "Session Manager plugin"; then
    local plugin_output
    plugin_output="$(mktemp)"
    if run_capture "$plugin_output" session-manager-plugin; then
      pass "Session Manager plugin can be executed"
    else
      fail "Session Manager plugin is installed but could not execute"
      sed 's/^/      /' "$plugin_output"
      mark_tooling_failure
    fi
    rm -f "$plugin_output"
  fi

  if ! command -v aws >/dev/null 2>&1; then
    fail "Skipping AWS CLI configuration checks because aws is unavailable"
    mark_tooling_failure
    return
  fi

  resolve_region

  info "Requested profile: ${PROFILE:-<default>}"
  info "Resolved region: $RESOLVED_REGION"

  local configure_output
  configure_output="$(mktemp)"
  if run_aws_capture "$configure_output" configure list; then
    pass "AWS CLI configuration is readable"
  else
    fail "AWS CLI configuration could not be read"
    mark_tooling_failure
  fi
  sed 's/^/      /' "$configure_output"
  rm -f "$configure_output"

  local region_output
  region_output="$(mktemp)"
  if run_aws_capture "$region_output" configure get region; then
    local configured_region
    configured_region="$(tr -d '\r\n' <"$region_output")"
    if [[ -n "$configured_region" ]]; then
      pass "AWS configured region: $configured_region"
    else
      warn "AWS CLI has no configured region; using $RESOLVED_REGION"
    fi
  else
    warn "Could not query AWS configured region; using $RESOLVED_REGION"
  fi
  rm -f "$region_output"
}

check_aws_identity() {
  section "AWS Identity"

  if ! command -v aws >/dev/null 2>&1; then
    fail "Skipping AWS identity check because aws is unavailable"
    mark_aws_identity_failure
    return
  fi

  local identity_output
  identity_output="$(mktemp)"
  if run_aws_capture "$identity_output" sts get-caller-identity --output text --query '[Account,Arn,UserId]'; then
    read -r AWS_ACCOUNT AWS_ARN AWS_USER_ID <"$identity_output"
    AWS_IDENTITY_OK=1
    pass "AWS credentials are valid"
    info "Account: $AWS_ACCOUNT"
    info "ARN: $AWS_ARN"
    info "UserId: $AWS_USER_ID"
  else
    fail "AWS credentials are invalid, expired, or not authorized for sts:GetCallerIdentity"
    sed 's/^/      /' "$identity_output"
    info "Remediation: refresh ~/.aws/credentials, run aws configure/sso login, or select the intended --profile."
    mark_aws_identity_failure
  fi
  rm -f "$identity_output"
}

resolve_instance_by_name_tag() {
  local lookup_output
  lookup_output="$(mktemp)"

  if ! run_aws_capture "$lookup_output" ec2 describe-instances \
    --filters "Name=tag:Name,Values=$NAME_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text; then
    fail "Could not query EC2 instances by Name tag: $NAME_TAG"
    sed 's/^/      /' "$lookup_output"
    rm -f "$lookup_output"
    return 1
  fi

  local instance_ids
  instance_ids="$(tr '\t' '\n' <"$lookup_output" | sed '/^$/d')"
  local count
  count="$(printf '%s\n' "$instance_ids" | sed '/^$/d' | wc -l)"

  if [[ "$count" -eq 0 ]]; then
    fail "No EC2 instance found with Name tag: $NAME_TAG"
    rm -f "$lookup_output"
    return 1
  fi

  if [[ "$count" -gt 1 ]]; then
    fail "Multiple EC2 instances found with Name tag: $NAME_TAG; use --instance-id"
    printf '%s\n' "$instance_ids" | sed 's/^/      /'
    rm -f "$lookup_output"
    return 1
  fi

  INSTANCE_ID="$instance_ids"
  pass "Resolved Name tag '$NAME_TAG' to instance $INSTANCE_ID"
  rm -f "$lookup_output"
}

check_instance_exists() {
  local instance_output
  instance_output="$(mktemp)"

  if run_aws_capture "$instance_output" ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress,IamInstanceProfile.Arn]' \
    --output text; then
    pass "EC2 instance exists: $INSTANCE_ID"
    sed 's/^/      /' "$instance_output"
    rm -f "$instance_output"
    return 0
  fi

  fail "EC2 instance does not exist or cannot be described: $INSTANCE_ID"
  sed 's/^/      /' "$instance_output"
  rm -f "$instance_output"
  return 1
}

check_ssm_managed_instance() {
  local ssm_output
  ssm_output="$(mktemp)"

  if run_aws_capture "$ssm_output" ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].[InstanceId,PingStatus,PlatformType,AgentVersion,IamRole]' \
    --output text; then
    local ssm_result
    ssm_result="$(tr -d '\r' <"$ssm_output")"
    if [[ -n "$ssm_result" && "$ssm_result" != "None" ]]; then
      pass "Instance is registered with AWS Systems Manager"
      printf '%s\n' "$ssm_result" | sed 's/^/      /'
      rm -f "$ssm_output"
      return 0
    fi
  fi

  fail "Instance is not visible as an SSM managed instance: $INSTANCE_ID"
  sed 's/^/      /' "$ssm_output"
  info "Remediation: attach AmazonSSMManagedInstanceCore, ensure SSM agent is running, and provide outbound access through NAT or SSM VPC endpoints."
  rm -f "$ssm_output"
  return 1
}

run_ssm_command() {
  local send_output
  send_output="$(mktemp)"

  if ! run_aws_capture "$send_output" ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "devops bootcamp preflight check" \
    --parameters 'commands=["echo ssm-ok","hostname"]' \
    --query 'Command.CommandId' \
    --output text; then
    fail "Could not send SSM command to $INSTANCE_ID"
    sed 's/^/      /' "$send_output"
    info "Remediation: confirm the instance is online, SSM-managed, and your AWS identity has ssm:SendCommand permission."
    rm -f "$send_output"
    return 1
  fi

  local command_id
  command_id="$(tr -d '\r\n' <"$send_output")"
  rm -f "$send_output"

  if [[ -z "$command_id" || "$command_id" == "None" ]]; then
    fail "SSM send-command returned no command ID"
    return 1
  fi

  pass "Sent SSM command: $command_id"

  local status="Pending"
  local invocation_output
  invocation_output="$(mktemp)"

  for _ in $(seq 1 24); do
    if run_aws_capture "$invocation_output" ssm get-command-invocation \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query '[Status,StandardOutputContent,StandardErrorContent]' \
      --output text; then
      status="$(awk 'NR==1 { print $1 }' "$invocation_output")"
      case "$status" in
        Success|Cancelled|TimedOut|Failed|Cancelling)
          break
          ;;
      esac
    fi
    sleep 5
  done

  if [[ "$status" == "Success" ]]; then
    pass "SSM command completed successfully"
    sed 's/^/      /' "$invocation_output"
    rm -f "$invocation_output"
    return 0
  fi

  fail "SSM command did not complete successfully; final status: $status"
  sed 's/^/      /' "$invocation_output"
  info "Remediation: check SSM agent health, IAM permissions, instance network egress, and CloudWatch/SSM command logs."
  rm -f "$invocation_output"
  return 1
}

check_ssm_instance() {
  section "SSM Instance"

  if [[ -z "$INSTANCE_ID" && -z "$NAME_TAG" ]]; then
    info "No --instance-id or --name-tag provided; skipping SSM instance test."
    return
  fi

  if [[ "$AWS_IDENTITY_OK" -ne 1 ]]; then
    fail "Skipping SSM instance test because AWS identity is not valid"
    mark_ssm_failure
    return
  fi

  if [[ -n "$NAME_TAG" ]]; then
    if ! resolve_instance_by_name_tag; then
      mark_ssm_failure
      return
    fi
  fi

  if ! check_instance_exists; then
    mark_ssm_failure
    return
  fi

  if ! check_ssm_managed_instance; then
    mark_ssm_failure
    return
  fi

  if ! run_ssm_command; then
    mark_ssm_failure
    return
  fi
}

print_summary() {
  section "Summary"
  info "Checks run: $CHECKS_TOTAL"
  info "Checks failed: $CHECKS_FAILED"
  info "Profile: ${PROFILE:-<default>}"
  info "Region: ${RESOLVED_REGION:-<unknown>}"

  if [[ "$AWS_IDENTITY_OK" -eq 1 ]]; then
    info "AWS account: $AWS_ACCOUNT"
    info "AWS ARN: $AWS_ARN"
  fi

  if [[ "$TOOLING_FAILED" -eq 0 && "$AWS_IDENTITY_FAILED" -eq 0 && "$SSM_FAILED" -eq 0 ]]; then
    pass "Preflight passed"
    return 0
  fi

  if [[ "$SSM_FAILED" -ne 0 && "$TOOLING_FAILED" -eq 0 && "$AWS_IDENTITY_FAILED" -eq 0 ]]; then
    fail "Preflight failed at SSM instance connectivity"
    return 2
  fi

  fail "Preflight failed at tooling, GitHub, AWS CLI, or AWS identity"
  return 1
}

main() {
  parse_args "$@"

  check_github
  check_aws_cli
  check_aws_identity
  check_ssm_instance
  print_summary
}

main "$@"
