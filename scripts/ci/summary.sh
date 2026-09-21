#!/usr/bin/env bash
set -euo pipefail

num() { local f="$1"; [ -s "$f" ] && tr -cd '0-9' < "$f" || printf '0'; }
json_num() { local f="$1" k="$2"; [ -s "$f" ] && jq -r ".$k // 0" "$f" 2>/dev/null || printf '0'; }
status() { local f="$1"; [ -s "$f" ] && cat "$f" || printf 'skipped'; }

ACTION="${ACTION:-plan}"
PROFILE="${PROFILE:-core}"
OVERALL="${OVERALL:-unknown}"
{
  echo "# Dash0 EKS lifecycle"
  echo
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Action | \`$ACTION\` |"
  echo "| Profile | \`$PROFILE\` |"
  echo "| Environment | \`aws-demo\` |"
  echo "| Overall result | **$OVERALL** |"
  echo
  echo "## Stage results"
  echo "| Validate | Backend | Plan | Change | Readiness | Dash0 | Cleanup |"
  echo "|---|---|---|---|---|---|---|"
  echo "| $(status .ci/validate.status) | $(status .ci/backend.status) | $(status .ci/plan.status) | $(status .ci/change.status) | $(status .ci/readiness.status) | $(status .ci/dash0.status) | $(status .ci/cleanup.status) |"
  echo
  echo "## Terraform resources"
  echo "| Planned additions | Planned changes | Planned destructions | State before | State after |"
  echo "|---:|---:|---:|---:|---:|"
  echo "| $(num .ci/add.count) | $(num .ci/change.count) | $(num .ci/destroy.count) | $(num .ci/state-before.count) | $(num .ci/state-after.count) |"
  echo
  echo "## Dash0 evidence"
  echo "| Collector ready | Metrics | Logs | Kubernetes events | Spans |"
  echo "|---:|---:|---:|---:|---:|"
  echo "| $(json_num .ci/dash0.json collector_ready) | $(json_num .ci/dash0.json metrics) | $(json_num .ci/dash0.json logs) | $(json_num .ci/dash0.json events) | $(json_num .ci/dash0.json spans) |"
  echo
  echo "## Remaining owned AWS resources"
  echo "| EKS | EC2 | NAT | ELBv2 | Classic ELB | EIP | ENI | EBS | Other tagged | Total |"
  echo "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
  echo "| $(json_num .ci/cleanup.json eks) | $(json_num .ci/cleanup.json ec2) | $(json_num .ci/cleanup.json nat) | $(json_num .ci/cleanup.json elbv2) | $(json_num .ci/cleanup.json classic_elb) | $(json_num .ci/cleanup.json eip) | $(json_num .ci/cleanup.json eni) | $(json_num .ci/cleanup.json ebs) | $(json_num .ci/cleanup.json other_tagged) | $(json_num .ci/cleanup.json total) |"
  echo
  echo "State bucket, GitHub OIDC provider and IAM role are retained (managed outside this workflow)."
} >> "$GITHUB_STEP_SUMMARY"
