# Dash0 on EKS — Observability Demo Lab

Terraform modules that stand up an EKS cluster wired into [Dash0](https://www.dash0.com)
through the Dash0 OpenTelemetry operator, with **toggleable technology profiles**
so you can demo one stack at a time (Istio, Cilium, ArgoCD, Kafka, Postgres,
gateways) without them fighting each other.

Built for recording hands-on content: enable a profile, apply, show the telemetry
land in Dash0, move on.

**Repository:** <https://github.com/arumullayaswanth/Dash0>

```bash
git clone https://github.com/arumullayaswanth/Dash0.git
```

Operate everything from **GitHub → Actions → Dash0 EKS lifecycle** after the
one-time setup in [deploy.md](deploy.md). Nothing needs to run on your laptop.

---

## Why profiles instead of "install everything"

Several of these technologies genuinely conflict on one cluster:

| Conflict | Reason |
|---|---|
| Istio vs Linkerd | Both inject a sidecar into every pod and fight over the same iptables rules |
| Cilium vs AWS VPC CNI | Cilium must replace the CNI — a cluster-creation decision, not a toggle |
| Envoy Gateway vs kgateway | Each ships and owns the Gateway API CRDs |
| Istio vs Emissary | mTLS STRICT breaks Emissary's health checks |
| Traefik / nginx / Contour / HAProxy | No conflict, but each provisions its own billable load balancer |

Each group sits behind a feature flag, and `modules/platform-addons/guards.tf`
rejects the broken combinations at plan time with an explanation. Those are
lifecycle preconditions, not `check` blocks, so they are hard errors rather than
warnings you can apply straight past.

Prometheus is a special case: it is not a conflict and not a competitor here.
Dash0's collector scrapes the ServiceMonitors that kube-prometheus-stack installs,
so the interesting demo is "your existing Prometheus config, different
destination". See the `observability` profile.

---

## Layout

```
.
├── modules/
│   ├── network/                # VPC, subnets, NAT, S3 endpoint, EKS+Karpenter subnet tags
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── eks-cluster/            # EKS v21, node groups, addons, EBS CSI IRSA, Karpenter IAM
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── dash0/                  # operator, collector config, monitoring CRs, token as a Secret
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── bastion/                # optional SSM EC2 jump host with kubectl/helm to inspect the cluster
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── helm-addon/             # one consistent way to install a chart + label its namespace
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── platform-addons/        # the technology catalog and every profile
│       ├── catalog.tf          #   pinned chart versions, all verified against upstream
│       ├── locals.tf           #   shared collector endpoint, storage, resource sizes
│       ├── guards.tf           #   conflict preconditions
│       ├── platform.tf         #   cert-manager, metrics-server, Karpenter + NodePool
│       ├── mesh.tf             #   Cilium | Istio | Linkerd
│       ├── ingress.tf          #   Traefik | nginx | Contour | Emissary | HAProxy
│       ├── gateways.tf         #   Envoy Gateway | kgateway | agentgateway
│       ├── gitops.tf           #   ArgoCD | FluxCD | Atlantis
│       ├── data-stores.tf      #   Postgres, MySQL, RabbitMQ, Kafka, ClickHouse, TigerData
│       ├── observability.tf    #   Prometheus, Grafana, Perses, KEDA, Kyverno, Dapr, Keycloak
│       ├── storage.tf          #   dash0-gp3 StorageClass that tags dynamic EBS volumes
│       ├── demo-app.tf         #   OpenTelemetry Demo, retargeted at the Dash0 collector
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── terraform/
│   └── live/                   # the root stack that composes the modules
│       ├── main.tf
│       ├── providers.tf
│       ├── versions.tf         #   provider pins + S3 backend
│       ├── variables.tf
│       ├── outputs.tf
│       ├── backend.hcl.example
│       ├── terraform.tfvars.example
│       └── env/                #   one tfvars per demo segment
│           ├── core.tfvars
│           ├── mesh-istio.tfvars
│           ├── network-cilium.tfvars
│           ├── gitops.tfvars
│           ├── data.tfvars
│           ├── observability.tfvars
│           └── everything.tfvars
├── dash0-assets/
│   └── eks-overview.yaml       # managed Dash0 dashboard (applied on apply, deleted on destroy)
├── .github/workflows/
│   └── terraform.yml           # the single plan/apply/destroy lifecycle workflow
├── scripts/
│   ├── verify-dash0.sh         # strict telemetry verification (metrics/logs/events/spans)
│   └── ci/                     # workflow helpers
│       ├── backend.sh          #   ensure/delete the encrypted S3 state backend
│       ├── wait-ready.sh       #   block until nodes and workloads are ready
│       ├── cleanup.sh          #   drain K8s + verify/remove owned AWS orphans
│       └── summary.sh          #   write the GitHub job summary
├── docs/                       # SETUP, DEMO-RUNBOOK, COSTS
├── deploy.md                   # click-by-click setup, operation, recording, teardown
└── README.md
```

---

## Deploy

Complete the one-time AWS OIDC, protected GitHub environment, and Dash0 secret setup in [deploy.md](deploy.md). After that, all recurring operations use the single **Dash0 EKS lifecycle** workflow under **GitHub → Actions**:

- `plan` previews the selected profile.
- `apply` creates/updates EKS, waits for readiness, and verifies metrics, logs, Kubernetes events, and spans in Dash0.
- `destroy` drains Kubernetes-managed AWS resources, applies a saved destroy plan, removes owned orphans, and publishes zero-resource evidence.

No local Terraform, Helm, kubectl, or AWS CLI command is required for normal operation.

The workflow deploys the `core` stack in one run: VPC, EKS, node group, bastion,
cert-manager, metrics-server, the Dash0 operator and collector, and the
OpenTelemetry Demo as a traffic source. Roughly $0.35/hour, 20–30 minutes.

The optional technology profiles (Istio, Cilium, GitOps, data stores, Prometheus)
still exist in `modules/platform-addons` behind feature flags in
`terraform/live/env/core.tfvars`. Edit that file to enable more, and mind the
conflict rules in `modules/platform-addons/guards.tf`.

What is worth showing on camera is in [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md).

---

## Dash0 credentials

Three values from <https://app.dash0.com> → organization settings:

| Value | Location | Shape |
|---|---|---|
| OTLP/gRPC endpoint | Endpoints → OTLP/gRPC | `ingress.<region>.aws.dash0.com:4317` |
| API endpoint | Endpoints → API | `https://api.<region>.aws.dash0.com` |
| Auth token | Auth Tokens | `auth_...`, no `Bearer ` prefix |

The token goes into a Kubernetes Secret and is referenced via `secretRef`. The
chart also accepts `operator.dash0Export.token`, which renders it verbatim into a
ConfigMap readable by anyone with cluster read access — this repo deliberately does
not use that path.

`*.tfvars` is gitignored except `env/`, so a token cannot be committed by accident.

---

## Verified, not assumed

Chart versions in `catalog.tf`, the Terraform module versions, the GitHub Action
pins and the in-cluster collector service name were all read from upstream rather
than recalled. The collector endpoint
(`dash0-operator-opentelemetry-collector-service`, ports 4317/4318) comes from the
operator's own source, because the Service is created by the operator at runtime
and does not appear in `helm template` output.

Every module and all seven profile combinations pass `terraform validate`, and the
conflict preconditions were confirmed to block a bad plan.

Not verified: nothing has been applied to AWS. No cluster has been created, no
telemetry has reached a real Dash0 org. The first `terraform apply` is still an
untested path, and chart value schemas can drift.

---

## Cost warning

Real, billable infrastructure: an EKS control plane (~$0.10/hour the moment it
exists), NAT gateway, EC2 nodes, EBS volumes and load balancers. Baseline is about
$0.15/hour before any nodes.

Select `destroy` in **Dash0 EKS lifecycle** (with `confirm = yes`) when recording is finished. The workflow deletes LoadBalancer services and persistent workloads before EKS, waits for AWS cleanup, checks tagged orphans, and fails if any billable demo resource remains. The S3 state bucket is left alone; delete it manually if you no longer need it.

Full breakdown and cleanup checks in [docs/COSTS.md](docs/COSTS.md).

---

## Architecture diagram prompt

Paste the following into an image/diagram generator (ChatGPT/DALL·E, Gemini,
Excalidraw AI, Eraser.io, etc.) to produce the project architecture diagram.

### Prompt (full architecture)

```
Create a clean, professional cloud architecture diagram titled
"Dash0 on EKS — Observability Demo Lab".

Layout left to right, three zones:

ZONE 1 — Developer / CI (left):
- A GitHub repository box "arumullayaswanth/Dash0".
- A "GitHub Actions: Dash0 EKS lifecycle" box with one workflow that has three
  actions: plan, apply, destroy.
- An arrow labeled "OIDC (no static keys)" from GitHub Actions to AWS IAM.

ZONE 2 — AWS account (center, large box labeled "AWS Region us-east-1"):
- IAM OIDC provider + IAM role "github-dash0-eks-demo".
- S3 bucket "Terraform state (encrypted, versioned)".
- A VPC box spanning 2 Availability Zones containing:
  - Public subnets with a NAT Gateway and internet-facing Network Load Balancers.
  - Private subnets containing an "EKS managed node group" and an
    "SSM Bastion EC2 (kubectl/helm)".
  - Intra subnets containing the "EKS control plane ENIs".
- An "Amazon EKS cluster (dash0-lab-demo)" box overlaying the private subnets.

Inside the EKS cluster box, show these components as small labeled tiles:
- "Dash0 Operator" and its "OpenTelemetry Collector (DaemonSet)".
- "OpenTelemetry Demo (~15 microservices, load generator)".
- Optional profile tiles grouped and dimmed: Service Mesh (Istio | Linkerd),
  CNI (Cilium), Ingress (Traefik | NGINX | Contour | Emissary | HAProxy),
  Gateways (Envoy Gateway | kgateway | agentgateway),
  GitOps (ArgoCD | FluxCD | Atlantis),
  Data (PostgreSQL, MySQL, RabbitMQ, Kafka, ClickHouse, TimescaleDB),
  Observability (Prometheus, Grafana, Perses, KEDA, Kyverno, Dapr, Keycloak),
  Compute (Karpenter).

ZONE 3 — Dash0 SaaS (right):
- A "Dash0 (OpenTelemetry-native observability)" box.
- Show views: Kubernetes infrastructure, Service Map, Traces, Logs,
  Kubernetes Events, Host Metrics, and a custom "EKS Overview" dashboard.

Data flow arrows:
- All in-cluster components -> Dash0 Collector (OTLP).
- Dash0 Collector -> Dash0 SaaS over "OTLP/gRPC :4317 (auth token)".
- GitHub Actions -> EKS API for apply/verify/destroy.
- Bastion EC2 -> EKS API via kubectl (reached through AWS SSM Session Manager).
- Terraform -> S3 state bucket.

Style: modern flat vector, official AWS/Kubernetes/Dash0-style iconography,
labeled arrows, subtle zone backgrounds, high contrast, 16:9, presentation quality.
```

### Prompt (simple flow, for a thumbnail)

```
Simple left-to-right flow diagram, flat vector, 16:9:
GitHub Actions (OIDC) -> AWS EKS cluster (Dash0 Operator + OpenTelemetry Demo)
-> OpenTelemetry Collector -> Dash0 dashboards (traces, logs, metrics, events).
Include a small "SSM Bastion (kubectl)" box connected to the EKS cluster.
Title: "Dash0 on EKS Observability Demo". Clean, minimal, high contrast.
```

Save the generated image to `docs/architecture.png` and reference it here with
`![Architecture](docs/architecture.png)`.
