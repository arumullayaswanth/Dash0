# Costs

This provisions real, billable AWS infrastructure. Read this before leaving a
cluster running overnight.

Figures are `us-east-1` on-demand list prices and are estimates for planning, not
a quote. Check the [EKS pricing page](https://aws.amazon.com/eks/pricing/) and
[VPC pricing page](https://aws.amazon.com/vpc/pricing/) for current numbers.

---

## Fixed, regardless of profile

| Item | Rate | Per hour | Per month |
|---|---|---|---|
| EKS control plane | $0.10/hour per cluster | $0.10 | ~$73 |
| NAT gateway (1, shared) | ~$0.045/hour + data | ~$0.05 | ~$33 |
| **Baseline** | | **~$0.15** | **~$106** |

The control plane charge starts the moment the cluster exists and does not stop
for idle clusters or zero nodes.

One NAT gateway is a deliberate choice in `network/main.tf`. Per-AZ NAT would add
about $33/month each. It makes the cluster dependent on a single AZ for egress,
which is the right trade for a demo and the wrong one for production.

The optional bastion (`enable_bastion = true`, default) adds one small EC2
instance, `t3.small` at ~$0.021/hour (~$0.17 per 8-hour day). `destroy` removes
it. Set `enable_bastion = false` to skip it.

---

## Per profile

Compute assumes on-demand `m6i.large` at ~$0.096/hour and `m6i.xlarge` at
~$0.192/hour.

| Profile | Nodes | Compute/hr | LBs | Total/hr | 8-hour day |
|---|---|---|---|---|---|
| core | 2 × large | ~$0.19 | 0 | **~$0.35** | ~$2.80 |
| gitops | 3 × large | ~$0.29 | 0 | **~$0.45** | ~$3.60 |
| mesh-istio | 2 × xlarge | ~$0.38 | 2 | **~$0.58** | ~$4.65 |
| network-cilium | 2 × xlarge | ~$0.38 | 0 | **~$0.53** | ~$4.25 |
| observability | 3 × xlarge | ~$0.58 | 0 | **~$0.73** | ~$5.85 |
| data | 2-4 × xlarge | ~$0.38-0.77 | 0 | **~$0.55-0.95** | ~$4.40-7.60 |
| everything | 4-8 × xlarge | ~$0.77-1.54 | 4 | **~$1.60-2.45** | ~$13-20 |

Add roughly $0.025/hour per network load balancer, plus data processing.

---

## Easy to forget

**Load balancers outlive the cluster.** Every `Service` of type LoadBalancer
creates an AWS NLB that Terraform does not own. If you destroy the cluster without
deleting those services first, the NLBs keep billing and their ENIs can block the
VPC from deleting.

```bash
terraform output load_balancer_services   # what is currently provisioned
```

**EBS volumes outlive their pods.** PersistentVolumeClaims from the `data` and
`observability` profiles create gp2 volumes at ~$0.08/GiB-month. At 8Gi each that
is cents, but they persist after a destroy if the PVC was not deleted cleanly.

**CloudWatch log ingest.** The cluster ships `api`, `audit` and `authenticator`
control plane logs at ~$0.50/GB ingested. Audit logs on a busy cluster are the
surprising one. Retention is 7 days by default. To cut it:

```hcl
# in the eks_cluster module call
enabled_log_types = ["api"]
```

**NAT data processing.** ~$0.045/GB. Image pulls are the bulk of it. The free S3
gateway endpoint is always created, which covers ECR layer downloads, so this
mostly stays small. Interface endpoints for the ECR API and STS are available via
`enable_interface_endpoints = true`, but they bill hourly per AZ and are usually
not worth it for a short-lived cluster.

---

## Reducing spend

**Stop compute, keep the cluster:**

```bash
terraform apply -var-file=env/core.tfvars \
  -var system_node_desired=0 -var system_node_min=0
```

Leaves the ~$0.15/hour baseline. Good between recording sessions on the same day.

**Enable Karpenter and let it use spot:**

```hcl
enable_karpenter = true
```

The NodePool in `platform-addons/platform.tf` prefers spot over on-demand and
consolidates underutilised nodes after a minute. Spot typically runs 60-70% below
on-demand. Interruptions are handled through an SQS queue, and an interruption is
itself a decent thing to observe in Dash0.

**Destroy fully:**

```bash
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer
sleep 90
terraform destroy -var-file=env/core.tfvars
```

The order matters, for the reason above.

---

## Confirm nothing is left

```bash
# Load balancers
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[].[LoadBalancerName,State.Code]" --output table

# Unattached volumes
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query "Volumes[].[VolumeId,Size]" --output table

# Any EKS cluster still alive
aws eks list-clusters

# NAT gateways
aws ec2 describe-nat-gateways \
  --filter Name=state,Values=available \
  --query "NatGateways[].NatGatewayId" --output table
```

The destroy workflow runs equivalent checks and prints them in the job summary.

---

## Set a billing alarm

Worth doing once, before the first apply:

```bash
aws budgets create-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget '{
    "BudgetName": "dash0-lab-monthly",
    "BudgetLimit": {"Amount": "50", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }'
```

Then add a notification subscriber so it actually emails you at 80%.
