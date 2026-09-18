#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-verify}"
PROJECT="${PROJECT:-dash0-lab}"
ENVIRONMENT="${ENVIRONMENT:-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-${PROJECT}-${ENVIRONMENT}}"
OUT="${CLEANUP_RESULT_FILE:-cleanup.json}"

# Resource Groups Tagging API gives the ownership set without touching unrelated
# account resources. Some service-managed resources need service-specific scans.
tagged_arns() {
  aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Project,Values=$PROJECT" "Key=Environment,Values=$ENVIRONMENT" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n'
}

scan() {
  local arns
  arns=$(tagged_arns || true)

  EKS=$(aws eks list-clusters --query "clusters[?@=='$CLUSTER_NAME']" --output json | jq 'length')
  EC2=$(aws ec2 describe-instances --filters \
    "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" \
    'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down' \
    --query 'Reservations[].Instances[].InstanceId' --output json | jq 'length')
  NAT=$(aws ec2 describe-nat-gateways --filter \
    "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" \
    'Name=state,Values=pending,available,deleting' --query 'NatGateways[].NatGatewayId' --output json | jq 'length')
  EIP=$(aws ec2 describe-addresses --filters \
    "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" \
    --query 'Addresses[].AllocationId' --output json | jq 'length')
  ENI=$(aws ec2 describe-network-interfaces --filters \
    "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' --output json | jq 'length')
  EBS=$(aws ec2 describe-volumes --filters \
    "Name=tag:Project,Values=$PROJECT" "Name=tag:Environment,Values=$ENVIRONMENT" \
    --query 'Volumes[].VolumeId' --output json | jq 'length')

  ELBV2=0
  while read -r arn; do
    [ -n "$arn" ] && [[ "$arn" == arn:aws:elasticloadbalancing:*:loadbalancer/* ]] && ELBV2=$((ELBV2 + 1))
  done <<<"$arns"
  while read -r arn; do
    [ -z "$arn" ] && continue
    if ! grep -qxF "$arn" <<<"$arns"; then ELBV2=$((ELBV2 + 1)); fi
  done < <(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n')

  CLASSIC_NAMES=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text)
  CLASSIC=0
  if [ -n "$CLASSIC_NAMES" ] && [ "$CLASSIC_NAMES" != "None" ]; then
    CLASSIC=$(aws elb describe-tags --load-balancer-names $CLASSIC_NAMES --output json 2>/dev/null \
      | jq --arg p "$PROJECT" --arg e "$ENVIRONMENT" --arg c "kubernetes.io/cluster/$CLUSTER_NAME" \
        '[.TagDescriptions[] | select(
          (any(.Tags[]; .Key=="Project" and .Value==$p) and any(.Tags[]; .Key=="Environment" and .Value==$e))
          or any(.Tags[]; .Key==$c and (.Value=="owned" or .Value=="shared"))
        )] | length')
  fi

  TAGGED_TOTAL=$(printf '%s\n' "$arns" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')
  KNOWN_TAGGED=$((EC2 + NAT + ELBV2 + EIP + ENI + EBS))
  OTHER_TAGGED=$((TAGGED_TOTAL > KNOWN_TAGGED ? TAGGED_TOTAL - KNOWN_TAGGED : 0))

  jq -nc --argjson eks "$EKS" --argjson ec2 "$EC2" --argjson nat "$NAT" \
    --argjson elbv2 "$ELBV2" --argjson classic "$CLASSIC" --argjson eip "$EIP" \
    --argjson eni "$ENI" --argjson ebs "$EBS" --argjson other "$OTHER_TAGGED" \
    '{eks:$eks,ec2:$ec2,nat:$nat,elbv2:$elbv2,classic_elb:$classic,eip:$eip,eni:$eni,ebs:$ebs,other_tagged:$other,total:($eks+$ec2+$nat+$elbv2+$classic+$eip+$eni+$ebs+$other)}' > "$OUT"
  cat "$OUT"
}
drain_cluster() {
  if ! aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "Cluster is absent; skipping Kubernetes drain."
    return
  fi
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

  # Services must disappear while their controllers and cluster still exist, or
  # cloud load balancers and ENIs can be orphaned.
  kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer -o json \
    | jq -r '.items[] | [.metadata.namespace,.metadata.name] | @tsv' \
    | while IFS=$'\t' read -r namespace name; do
        [ -n "$namespace" ] && kubectl delete service "$name" -n "$namespace" --wait=false
      done

  # Deleting PVCs before EKS gives the CSI controller time to remove EBS volumes.
  kubectl delete statefulset --all --all-namespaces --wait=false --ignore-not-found
  kubectl delete pvc --all --all-namespaces --wait=false --ignore-not-found

  for _ in $(seq 1 40); do
    LB_COUNT=$(kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer -o json 2>/dev/null | jq '.items|length' || echo 0)
    CLOUD_LB_COUNT=$(aws resourcegroupstaggingapi get-resources \
      --tag-filters "Key=kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared" \
      --resource-type-filters elasticloadbalancing:loadbalancer \
      --query 'length(ResourceTagMappingList)' --output text 2>/dev/null || echo 0)
    [ "$LB_COUNT" -eq 0 ] && [ "$CLOUD_LB_COUNT" -eq 0 ] && break
    echo "Waiting for load balancers: services=$LB_COUNT aws=$CLOUD_LB_COUNT"
    sleep 15
  done
}

remove_owned_orphans() {
  # Terraform should remove these. This fallback acts only on exact demo tags or
  # the exact Kubernetes cluster ownership tag.
  if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
    NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[]' --output text 2>/dev/null || true)
    for group in $NODEGROUPS; do
      aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$group" >/dev/null || true
      aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" --nodegroup-name "$group" || true
    done
    FARGATE=$(aws eks list-fargate-profiles --cluster-name "$CLUSTER_NAME" --query 'fargateProfileNames[]' --output text 2>/dev/null || true)
    for profile in $FARGATE; do
      aws eks delete-fargate-profile --cluster-name "$CLUSTER_NAME" --fargate-profile-name "$profile" >/dev/null || true
      aws eks wait fargate-profile-deleted --cluster-name "$CLUSTER_NAME" --fargate-profile-name "$profile" || true
    done
    aws eks delete-cluster --name "$CLUSTER_NAME" >/dev/null || true
    aws eks wait cluster-deleted --name "$CLUSTER_NAME" || true
  fi

  while read -r arn; do
    [ -z "$arn" ] && continue
    case "$arn" in
      arn:aws:elasticloadbalancing:*:loadbalancer/app/*|arn:aws:elasticloadbalancing:*:loadbalancer/net/*)
        aws elbv2 delete-load-balancer --load-balancer-arn "$arn" || true ;;
    esac
  done < <(tagged_arns || true)
  while read -r arn; do
    [ -z "$arn" ] || aws elbv2 delete-load-balancer --load-balancer-arn "$arn" || true
  done < <(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n')

  CLASSIC_NAMES=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text)
  if [ -n "$CLASSIC_NAMES" ] && [ "$CLASSIC_NAMES" != "None" ]; then
    aws elb describe-tags --load-balancer-names $CLASSIC_NAMES --output json 2>/dev/null \
      | jq -r --arg p "$PROJECT" --arg e "$ENVIRONMENT" --arg c "kubernetes.io/cluster/$CLUSTER_NAME" \
        '.TagDescriptions[] | select(
          (any(.Tags[]; .Key=="Project" and .Value==$p) and any(.Tags[]; .Key=="Environment" and .Value==$e))
          or any(.Tags[]; .Key==$c and (.Value=="owned" or .Value=="shared"))
        ) | .LoadBalancerName' \
      | while read -r name; do [ -z "$name" ] || aws elb delete-load-balancer --load-balancer-name "$name"; done
  fi

  INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=$ENVIRONMENT" \
    'Name=instance-state-name,Values=pending,running,stopping,stopped' \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -z "$INSTANCE_IDS" ] || aws ec2 terminate-instances --instance-ids $INSTANCE_IDS >/dev/null

  NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=$ENVIRONMENT" 'Name=state,Values=pending,available' \
    --query 'NatGateways[].NatGatewayId' --output text)
  for id in $NAT_IDS; do aws ec2 delete-nat-gateway --nat-gateway-id "$id" >/dev/null; done

  IDS=$(aws ec2 describe-volumes --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=$ENVIRONMENT" 'Name=status,Values=available' \
    --query 'Volumes[].VolumeId' --output text)
  for id in $IDS; do aws ec2 delete-volume --volume-id "$id"; done

  ENIS=$(aws ec2 describe-network-interfaces --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=$ENVIRONMENT" 'Name=status,Values=available' \
    --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
  for id in $ENIS; do aws ec2 delete-network-interface --network-interface-id "$id" || true; done

  ALLOCS=$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=$ENVIRONMENT" --query 'Addresses[?AssociationId==null].AllocationId' --output text)
  for id in $ALLOCS; do aws ec2 release-address --allocation-id "$id"; done
}

case "$MODE" in
  drain) drain_cluster ;;
  cleanup)
    for attempt in $(seq 1 40); do
      remove_owned_orphans
      scan
      TOTAL=$(jq -r '.total' "$OUT")
      [ "$TOTAL" -eq 0 ] && exit 0
      echo "Owned resources are still deleting (attempt $attempt/40)."
      sleep 15
    done
    echo "Owned billable resources remain after cleanup timeout." >&2
    exit 1
    ;;
  verify)
    scan
    [ "$(jq -r '.total' "$OUT")" -eq 0 ]
    ;;
  *) echo "Usage: $0 drain|cleanup|verify" >&2; exit 2 ;;
esac
