###############################################################################
# Identity and tagging
###############################################################################

variable "project" {
  description = "Short project name, used as a prefix for every resource."
  type        = string
  default     = "dash0-lab"
}

variable "environment" {
  description = "Environment suffix, e.g. demo or dev."
  type        = string
  default     = "demo"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "repository_url" {
  description = "Git repository this stack lives in. Tagged onto resources so their origin is obvious in the console."
  type        = string
  default     = "local"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

###############################################################################
# Network
###############################################################################

variable "vpc_cidr" {
  description = "VPC CIDR. Needs room for VPC-CNI pod IPs."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway. Saves roughly $32/month per AZ avoided, at the cost of a single-AZ dependency."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create billed ECR/STS interface endpoints. Off by default; the free S3 gateway endpoint is always created."
  type        = bool
  default     = false
}

###############################################################################
# Cluster
###############################################################################

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.34"
}

variable "api_allowed_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public Kubernetes API endpoint.
    The default of 0.0.0.0/0 leaves the endpoint reachable from anywhere. It is
    still authenticated and authorised via EKS access entries, but narrowing this
    to your own IP plus the CI egress range is strongly preferred. GitHub-hosted
    runners use a wide, rotating IP range, which is the practical reason this
    defaults open.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ci_role_arn" {
  description = "IAM role ARN used by GitHub Actions. Granted cluster-admin via an EKS access entry. Null to skip."
  type        = string
  default     = null
}

variable "cni_mode" {
  description = <<-EOT
    Pod networking: "vpc-cni" (default) or "cilium".
    Changing this on a live cluster is disruptive; recreate instead.
  EOT
  type        = string
  default     = "vpc-cni"

  validation {
    condition     = contains(["vpc-cni", "cilium"], var.cni_mode)
    error_message = "cni_mode must be \"vpc-cni\" or \"cilium\"."
  }
}

variable "system_node_instance_types" {
  description = <<-EOT
    Instance types for the always-on system node group.
    m6i.large (2 vCPU / 8 GiB) fits the core profile plus the OTel demo. Heavier
    profiles (mesh + data stores) want m6i.xlarge or Karpenter turned on.
  EOT
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_min" {
  description = "Minimum system node count."
  type        = number
  default     = 2
}

variable "system_node_desired" {
  description = "Desired system node count."
  type        = number
  default     = 2
}

variable "system_node_max" {
  description = "Maximum system node count."
  type        = number
  default     = 6
}

variable "node_disk_size" {
  description = "Root volume size in GiB. Meshes and data stores pull a lot of images."
  type        = number
  default     = 50
}

variable "enable_karpenter" {
  description = <<-EOT
    Install Karpenter and let it provision nodes on demand.
    Recommended once you enable several profiles: it scales the cluster to the
    workload instead of you guessing a node count, and spot instances cut cost.
  EOT
  type        = bool
  default     = false
}

###############################################################################
# Dash0
###############################################################################

variable "dash0_otlp_grpc_endpoint" {
  description = "From app.dash0.com -> organization settings -> Endpoints -> OTLP/gRPC. Looks like ingress.<region>.aws.dash0.com:4317."
  type        = string
}

variable "dash0_api_endpoint" {
  description = "From app.dash0.com -> organization settings -> Endpoints -> API. Looks like https://api.<region>.aws.dash0.com."
  type        = string
}

variable "dash0_auth_token" {
  description = <<-EOT
    Dash0 auth token. Supply via TF_VAR_dash0_auth_token or a CI secret.
    Never put this in a tfvars file that gets committed.
  EOT
  type        = string
  sensitive   = true
}

variable "dash0_dataset" {
  description = "Dash0 dataset telemetry lands in. A dedicated dataset keeps demo noise out of \"default\"."
  type        = string
  default     = "default"
}

variable "instrument_workloads_mode" {
  description = <<-EOT
    Dash0 auto-instrumentation aggressiveness:
      "created-and-updated" - new/changed workloads only, no pod restarts (default)
      "all"                 - instrument existing workloads too, restarting them
      "none"                - metrics and logs only, no tracing injection
  EOT
  type        = string
  default     = "created-and-updated"
}

###############################################################################
# Technology profiles
#
# Each is an object of booleans. Layer them with -var-file, one file per demo
# segment. Conflicting combinations fail at plan time with an explanation.
###############################################################################

variable "profile_platform" {
  description = "Baseline plumbing. cert-manager is required by Linkerd, Emissary and kgateway."
  type = object({
    cert_manager   = optional(bool, true)
    metrics_server = optional(bool, true)
  })
  default = {}
}

variable "profile_mesh" {
  description = "Service mesh. At most one may be true."
  type = object({
    istio   = optional(bool, false)
    linkerd = optional(bool, false)
  })
  default = {}
}

variable "profile_ingress" {
  description = "Ingress controllers. Each provisions its own AWS load balancer."
  type = object({
    traefik       = optional(bool, false)
    ingress_nginx = optional(bool, false)
    contour       = optional(bool, false)
    emissary      = optional(bool, false)
    haproxy       = optional(bool, false)
  })
  default = {}
}

variable "profile_gateways" {
  description = "Gateway API implementations. envoy_gateway and kgateway conflict over CRD ownership."
  type = object({
    envoy_gateway = optional(bool, false)
    kgateway      = optional(bool, false)
    agentgateway  = optional(bool, false)
  })
  default = {}
}

variable "profile_gitops" {
  description = "GitOps and IaC automation. These coexist."
  type = object({
    argocd   = optional(bool, false)
    fluxcd   = optional(bool, false)
    atlantis = optional(bool, false)
  })
  default = {}
}

variable "profile_data_stores" {
  description = "Databases and brokers. All require PersistentVolumes."
  type = object({
    postgres   = optional(bool, false)
    mysql      = optional(bool, false)
    rabbitmq   = optional(bool, false)
    kafka      = optional(bool, false)
    clickhouse = optional(bool, false)
    tigerdata  = optional(bool, false)
  })
  default = {}
}

variable "profile_observability" {
  description = "Prometheus, Grafana, Perses, KEDA, Kyverno, Dapr, Keycloak."
  type = object({
    prometheus_stack = optional(bool, false)
    grafana          = optional(bool, false)
    perses           = optional(bool, false)
    keda             = optional(bool, false)
    kyverno          = optional(bool, false)
    dapr             = optional(bool, false)
    keycloak         = optional(bool, false)
  })
  default = {}
}

variable "keep_prometheus_server" {
  description = <<-EOT
    Run the Prometheus server, not just its CRDs and exporters.
    False is the more interesting demo: kube-state-metrics and node-exporter keep
    publishing ServiceMonitors and the Dash0 collector scrapes them directly, so
    existing Prometheus config works with no Prometheus server in the path.
  EOT
  type        = bool
  default     = true
}

variable "atlantis_repo_allowlist" {
  description = "Repos Atlantis may plan against, e.g. github.com/you/*."
  type        = string
  default     = "github.com/*/*"
}

variable "enable_demo_app" {
  description = "Install the OpenTelemetry Demo. This is the traffic source; without it Dash0 looks empty."
  type        = bool
  default     = true
}

###############################################################################
# Bastion
###############################################################################

variable "enable_bastion" {
  description = <<-EOT
    Create an SSM-managed EC2 bastion with kubectl/helm/aws preinstalled and
    cluster-admin access. Connect from the AWS Console via Session Manager to
    inspect the cluster. Adds a small always-on EC2 cost while enabled.
  EOT
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Bastion instance type. t3.small is enough for kubectl/helm."
  type        = string
  default     = "t3.small"
}

###############################################################################
# Storage
###############################################################################

variable "storage_class" {
  description = "StorageClass for stateful charts. dash0-gp3 stamps ownership tags on dynamic EBS volumes."
  type        = string
  default     = "dash0-gp3"
}

variable "data_store_volume_size" {
  description = "PersistentVolume size for demo data stores."
  type        = string
  default     = "8Gi"
}
