###############################################################################
# platform-addons inputs
#
# Everything installed *onto* the cluster. Each technology is a boolean toggle
# so a demo segment is one tfvars file, and conflicting stacks can be rejected
# at plan time rather than discovered at 3am in a broken cluster.
###############################################################################

variable "cluster_name" {
  description = "EKS cluster name. Used by Karpenter and for chart-level cluster identity."
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint. Cilium needs it for kube-proxy replacement."
  type        = string
}

variable "region" {
  description = "AWS region, passed to charts that need it (Karpenter, Cilium ENI mode)."
  type        = string
}

# ----------------------------------------------------------------- networking

variable "cni_mode" {
  description = "Must match the value given to the eks-cluster module. Determines whether Cilium owns pod networking."
  type        = string
  default     = "vpc-cni"

  validation {
    condition     = contains(["vpc-cni", "cilium"], var.cni_mode)
    error_message = "cni_mode must be \"vpc-cni\" or \"cilium\"."
  }
}

variable "cluster_service_cidr" {
  description = "Service CIDR of the cluster. Required when Cilium replaces kube-proxy."
  type        = string
  default     = null
}

# --------------------------------------------------------------------- compute

variable "karpenter" {
  description = <<-EOT
    Karpenter wiring produced by the eks-cluster module's `karpenter` output.
    Pass null to leave Karpenter uninstalled.
  EOT
  type = object({
    service_account       = string
    iam_role_arn          = string
    node_iam_role_name    = string
    instance_profile_name = string
    queue_name            = string
  })
  default = null
}

# ------------------------------------------------------------------- profiles

variable "platform" {
  description = "Baseline cluster plumbing. cert-manager is a hard dependency of several other charts."
  type = object({
    cert_manager   = optional(bool, true)
    metrics_server = optional(bool, true)
  })
  default = {}
}

variable "mesh" {
  description = <<-EOT
    Service mesh selection. At most one of istio/linkerd may be true; they both
    inject sidecars and will fight over the same pods.
  EOT
  type = object({
    istio   = optional(bool, false)
    linkerd = optional(bool, false)
  })
  default = {}
}

variable "ingress" {
  description = <<-EOT
    Ingress controllers. Each enabled controller provisions its own AWS network
    load balancer, so enabling several is billable but not broken. Only one
    should own a given Ingress class.
  EOT
  type = object({
    traefik       = optional(bool, false)
    ingress_nginx = optional(bool, false)
    contour       = optional(bool, false)
    emissary      = optional(bool, false)
    haproxy       = optional(bool, false)
  })
  default = {}
}

variable "gateways" {
  description = <<-EOT
    Gateway API implementations. envoy_gateway and kgateway both install Gateway
    API CRDs, so enabling both together conflicts on CRD ownership.
  EOT
  type = object({
    envoy_gateway = optional(bool, false)
    kgateway      = optional(bool, false)
    agentgateway  = optional(bool, false)
  })
  default = {}
}

variable "gitops" {
  description = "GitOps and IaC automation controllers. These coexist happily."
  type = object({
    argocd   = optional(bool, false)
    fluxcd   = optional(bool, false)
    atlantis = optional(bool, false)
  })
  default = {}
}

variable "data_stores" {
  description = <<-EOT
    Databases and brokers. Every one of these claims a PersistentVolume, so the
    EBS CSI driver must be enabled on the cluster or the pods stay Pending.
  EOT
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

variable "observability" {
  description = <<-EOT
    The "teach the concept" layer. Prometheus here is not a Dash0 replacement:
    the Dash0 collector scrapes its ServiceMonitors, which is the more
    interesting story to show on camera.
  EOT
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
    Run the Prometheus server itself, not just its CRDs and exporters.
    Setting this false is the more interesting demo: kube-state-metrics and
    node-exporter still publish ServiceMonitors, and the Dash0 collector scrapes
    them directly, so existing Prometheus config keeps working with no
    Prometheus server in the path.
  EOT
  type        = bool
  default     = true
}

variable "demo_app" {
  description = "Install the OpenTelemetry Demo. This is the traffic source that makes Dash0 look alive."
  type        = bool
  default     = true
}

variable "otel_demo_chart_version" {
  description = "opentelemetry-demo chart version."
  type        = string
  default     = "0.41.2"
}

variable "otel_demo_use_own_collector" {
  description = <<-EOT
    Keep the demo chart's bundled OpenTelemetry Collector and Jaeger/Prometheus.
    Leave false so the demo exports straight to the Dash0 operator's collector,
    which is the point of the exercise.
  EOT
  type        = bool
  default     = false
}

# ----------------------------------------------------------------- storage

variable "atlantis_repo_allowlist" {
  description = <<-EOT
    Repositories Atlantis is allowed to plan against, e.g. "github.com/you/*".
    Atlantis refuses to start with the chart's placeholder value.
  EOT
  type        = string
  default     = "github.com/*/*"
}

variable "storage_class" {
  description = "StorageClass for stateful charts. dash0-gp3 is created by this module and stamps demo ownership tags."
  type        = string
  default     = "dash0-gp3"
}

variable "data_store_volume_size" {
  description = "PersistentVolume size for demo data stores. Small on purpose."
  type        = string
  default     = "8Gi"
}

variable "tags" {
  description = "Tags for any AWS resources created indirectly by charts that support tagging."
  type        = map(string)
  default     = {}
}
