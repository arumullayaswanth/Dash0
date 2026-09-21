#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-ensure}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is required}"
: "${AWS_REGION:?AWS_REGION is required}"

bucket_exists() {
  aws s3api head-bucket --bucket "$TF_STATE_BUCKET" >/dev/null 2>&1
}

verify_bucket() {
  # The state bucket is created manually in the AWS Console (see deploy.md).
  # The workflow only verifies it exists and is reachable; it does not create it.
  if ! bucket_exists; then
    echo "State bucket '$TF_STATE_BUCKET' was not found or is not accessible." >&2
    echo "Create it manually in the AWS S3 console (deploy.md Step 2a) and confirm" >&2
    echo "the assumed IAM role has s3 access to it, then re-run the workflow." >&2
    exit 1
  fi
  echo "Backend verified: s3://$TF_STATE_BUCKET"
}
case "$MODE" in
  verify) verify_bucket ;;
  *) echo "Usage: $0 verify" >&2; exit 2 ;;
esac
