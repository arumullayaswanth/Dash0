variable "cluster_name" {
  description = "Value reported as k8s.cluster.name on all telemetry. Lets you separate clusters in the Dash0 UI."
  type        = string
}

variable "otlp_grpc_endpoint" {
  description = <<-EOT
    Dash0 OTLP/gRPC ingress endpoint.
    Copy from app.dash0.com -> organization settings -> Endpoints -> OTLP/gRPC.
    Always starts with "ingress." and ends with "dash0.com:4317".
  EOT
  type        = string

  validation {
    condition     = can(regex("^(https://)?ingress\\..*dash0\\.com:4317$", var.otlp_grpc_endpoint))
    error_message = "otlp_grpc_endpoint must look like ingress.<region>.aws.dash0.com:4317."
  }
}

variable "api_endpoint" {
  description = <<-EOT
    Dash0 API base URL, used to sync dashboards and check rules (not telemetry).
    Copy from app.dash0.com -> organization settings -> Endpoints -> API.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://api\\..*dash0\\.com/?$", var.api_endpoint))
    error_message = "api_endpoint must look like https://api.<region>.aws.dash0.com."
  }
}

variable "auth_token" {
  description = <<-EOT
    Dash0 auth token from organization settings -> Auth Tokens.
    Do not include the "Bearer " prefix. Supply via TF_VAR_dash0_auth_token or a
    CI secret; never commit it to a tfvars file.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.auth_token) > 0
    error_message = "auth_token must not be empty."
  }
}

variable "dataset" {
  description = "Dash0 dataset that telemetry lands in. Using a per-cluster dataset keeps demo noise out of \"default\"."
  type        = string
  default     = "default"
}

variable "chart_version" {
  description = "dash0-operator Helm chart version."
  type        = string
  default     = "0.155.1"
}

variable "auto_monitor_namespaces" {
  description = "Monitor every namespace automatically unless it is labelled dash0.com/enable=false."
  type        = bool
  default     = true
}

variable "monitored_namespaces" {
  description = "Namespaces to create an explicit Dash0Monitoring resource in. Only used when auto_monitor_namespaces is false."
  type        = list(string)
  default     = []
}

variable "instrument_workloads_mode" {
  description = <<-EOT
    How aggressively to inject auto-instrumentation:
      "created-and-updated" - only new/changed workloads, no pod restarts (default).
      "all"                 - instrument existing workloads too, restarting their pods.
      "none"                - collect metrics/logs but do not inject tracing agents.
  EOT
  type        = string
  default     = "created-and-updated"

  validation {
    condition     = contains(["all", "created-and-updated", "none"], var.instrument_workloads_mode)
    error_message = "instrument_workloads_mode must be one of: all, created-and-updated, none."
  }
}

variable "enable_prometheus_scraping" {
  description = "Let the Dash0 collector scrape pods carrying prometheus.io/scrape annotations."
  type        = bool
  default     = true
}

variable "enable_prometheus_crd_support" {
  description = "Deploy the OTel target allocator so ServiceMonitor/PodMonitor/ScrapeConfig resources are scraped. Enable with the Prometheus profile."
  type        = bool
  default     = false
}

variable "enable_python_instrumentation" {
  description = "Enable Dash0 Python auto-instrumentation. Requires Python 3.10+ in the workload images."
  type        = bool
  default     = true
}

variable "cluster_ready" {
  description = <<-EOT
    Opaque gate value from the eks-cluster module's cluster_ready output. Forces
    every Kubernetes and Helm resource here to wait until EKS access entries
    have propagated, avoiding "forbidden" errors on the first apply.
  EOT
  type        = string
  default     = ""
}
