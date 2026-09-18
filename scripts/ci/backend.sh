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
delete_bucket() {
  if ! bucket_exists; then
    echo "Backend already absent."
    return
  fi

  # Versioned buckets require deletion of versions and delete markers in batches.
  while :; do
    VERSIONS=$(aws s3api list-object-versions --bucket "$TF_STATE_BUCKET" --output json)
    OBJECTS=$(jq -c '[((.Versions // []) + (.DeleteMarkers // []))[] | {Key:.Key,VersionId:.VersionId}]' <<<"$VERSIONS")
    COUNT=$(jq 'length' <<<"$OBJECTS")
    [ "$COUNT" -eq 0 ] && break
    aws s3api delete-objects --bucket "$TF_STATE_BUCKET" \
      --delete "$(jq -nc --argjson objects "$OBJECTS" '{Objects:$objects,Quiet:true}')" >/dev/null
  done

  aws s3api delete-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION"
  aws s3api wait bucket-not-exists --bucket "$TF_STATE_BUCKET"
  echo "Backend deleted: $TF_STATE_BUCKET"
}

case "$MODE" in
  verify) verify_bucket ;;
  delete) delete_bucket ;;
  *) echo "Usage: $0 verify|delete" >&2; exit 2 ;;
esac
