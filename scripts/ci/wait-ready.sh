#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS="${READINESS_TIMEOUT_SECONDS:-900}"
DEADLINE=$((SECONDS + TIMEOUT_SECONDS))

until kubectl wait --for=condition=Ready nodes --all --timeout=30s >/dev/null 2>&1; do
  [ "$SECONDS" -ge "$DEADLINE" ] && { kubectl get nodes -o wide; exit 1; }
  sleep 15
done

# Wait until every Deployment/StatefulSet has all desired replicas ready and all
# DaemonSets have all desired pods available. Completed Jobs do not block this.
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  DEP_BAD=$(kubectl get deployment --all-namespaces -o json | jq '[.items[] | select((.spec.replicas // 1) != (.status.readyReplicas // 0))] | length')
  STS_BAD=$(kubectl get statefulset --all-namespaces -o json | jq '[.items[] | select((.spec.replicas // 1) != (.status.readyReplicas // 0))] | length')
  DS_BAD=$(kubectl get daemonset --all-namespaces -o json | jq '[.items[] | select((.status.desiredNumberScheduled // 0) != (.status.numberReady // 0))] | length')
  POD_BAD=$(kubectl get pods --all-namespaces -o json | jq '[.items[] | select(.status.phase == "Pending" or .status.phase == "Unknown" or .status.phase == "Failed")] | length')

  if [ "$DEP_BAD" -eq 0 ] && [ "$STS_BAD" -eq 0 ] && [ "$DS_BAD" -eq 0 ] && [ "$POD_BAD" -eq 0 ]; then
    echo "All nodes and schedulable workloads are ready."
    exit 0
  fi
  echo "Waiting: deployments=$DEP_BAD statefulsets=$STS_BAD daemonsets=$DS_BAD pods=$POD_BAD"
  sleep 20
done

kubectl get nodes -o wide
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide || true
exit 1
