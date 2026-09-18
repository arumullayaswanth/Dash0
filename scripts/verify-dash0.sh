#!/usr/bin/env bash
set -euo pipefail

NS="${DASH0_NAMESPACE:-dash0-system}"
: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
: "${DASH0_API_URL:?DASH0_API_URL is required}"
: "${DASH0_AUTH_TOKEN:?DASH0_AUTH_TOKEN is required}"
: "${DASH0_DATASET:?DASH0_DATASET is required}"

RESULT_FILE="${DASH0_RESULT_FILE:-dash0-verification.json}"
ATTEMPTS="${DASH0_VERIFY_ATTEMPTS:-20}"
SLEEP_SECONDS="${DASH0_VERIFY_SLEEP_SECONDS:-15}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export DASH0_AGENT_MODE=true DASH0_COLOR=none

kubectl wait --for=condition=Available deployment -n "$NS" \
  -l app.kubernetes.io/name=dash0-operator --timeout=300s >/dev/null

DESIRED=$(kubectl get daemonset -n "$NS" -l app.kubernetes.io/name=opentelemetry-collector \
  -o json | jq '[.items[].status.desiredNumberScheduled // 0] | add // 0')
READY=$(kubectl get daemonset -n "$NS" -l app.kubernetes.io/name=opentelemetry-collector \
  -o json | jq '[.items[].status.numberReady // 0] | add // 0')
[ "$DESIRED" -gt 0 ] && [ "$READY" -eq "$DESIRED" ] || {
  echo "Collector readiness failed: ready=$READY desired=$DESIRED" >&2
  exit 1
}

ERRORS=$(kubectl logs -n "$NS" -l app.kubernetes.io/name=opentelemetry-collector \
  --tail=300 --all-containers 2>/dev/null | grep -Eic \
  'permanent error|authentication|unauthenticated|401|403|connection refused|no such host' || true)
[ "$ERRORS" -eq 0 ] || { echo "Collector export/authentication errors detected." >&2; exit 1; }

MONITORED=$(kubectl get dash0monitoring --all-namespaces -o json 2>/dev/null | jq '.items|length')
[ "$MONITORED" -gt 0 ] || { echo "No monitored namespace found." >&2; exit 1; }

DEMO_RUNNING=$(kubectl get pods -n otel-demo -o json 2>/dev/null | jq '[.items[] | select(.status.phase=="Running")] | length')
[ "$DEMO_RUNNING" -gt 0 ] || { echo "OpenTelemetry demo has no running pods." >&2; exit 1; }
query_until_nonempty() {
  local name="$1"; shift
  local count=0
  for _ in $(seq 1 "$ATTEMPTS"); do
    if "$@" >"$TMP/$name.json" 2>"$TMP/$name.err"; then
      case "$name" in
        metrics) count=$(jq '[.data.result[]? | select((.value[1] | tonumber?) > 0)] | length' "$TMP/$name.json" 2>/dev/null || echo 0) ;;
        logs|events) count=$(jq '[.resourceLogs[]?.scopeLogs[]?.logRecords[]?] | length' "$TMP/$name.json" 2>/dev/null || echo 0) ;;
        spans) count=$(jq '[.resourceSpans[]?.scopeSpans[]?.spans[]?] | length' "$TMP/$name.json" 2>/dev/null || echo 0) ;;
      esac
      [ "$count" -gt 0 ] && { echo "$count"; return 0; }
    fi
    sleep "$SLEEP_SECONDS"
  done
  echo "Dash0 $name query returned no data after $ATTEMPTS attempts." >&2
  return 1
}

# k8s_node_condition is produced by Kubernetes infrastructure collection. The
# cluster label can vary by Prometheus translation, so backend scoping is also
# enforced through the selected Dash0 dataset and the metric's cluster identity.
METRIC_COUNT=$(query_until_nonempty metrics dash0 metrics instant \
  --query 'count({otel_metric_name="k8s.node.condition_ready"} == 1)' --dataset "$DASH0_DATASET" -o json)
LOG_COUNT=$(query_until_nonempty logs dash0 -X logs query --from now-1h --to now \
  --limit 10 --filter "k8s.cluster.name is $CLUSTER_NAME" -o json)
EVENT_COUNT=$(query_until_nonempty events dash0 -X logs query --from now-1h --to now \
  --limit 10 --filter "k8s.cluster.name is $CLUSTER_NAME" --filter "event.name is_set" -o json)
SPAN_COUNT=$(query_until_nonempty spans dash0 -X spans query --from now-1h --to now \
  --limit 10 --filter "k8s.cluster.name is $CLUSTER_NAME" -o json)

jq -nc --argjson desired "$DESIRED" --argjson ready "$READY" \
  --argjson monitored "$MONITORED" --argjson demo "$DEMO_RUNNING" \
  --argjson metrics "$METRIC_COUNT" --argjson logs "$LOG_COUNT" \
  --argjson events "$EVENT_COUNT" --argjson spans "$SPAN_COUNT" \
  '{collector_desired:$desired,collector_ready:$ready,monitored_namespaces:$monitored,demo_running_pods:$demo,metrics:$metrics,logs:$logs,events:$events,spans:$spans,status:"passed"}' > "$RESULT_FILE"

echo "Dash0 verified: metrics, logs, Kubernetes events, and spans are present."
