variable "enabled" {
  description = "Whether to install this addon. Profiles flip this to layer technologies on and off."
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name."
  type        = string
}

variable "repository" {
  description = "Chart repository URL. For OCI charts pass the oci:// registry path; the chart name is appended automatically."
  type        = string
}

variable "chart" {
  description = "Chart name."
  type        = string
}

variable "chart_version" {
  description = "Pinned chart version. Always pin, so a re-apply weeks later reproduces the same demo."
  type        = string
}

variable "namespace" {
  description = "Namespace to install into."
  type        = string
}

variable "create_namespace" {
  description = "Create the namespace. Set false when several releases share one namespace (e.g. Istio components)."
  type        = bool
  default     = true
}

variable "monitored" {
  description = "Label the namespace so Dash0 auto-monitoring picks it up. False adds dash0.com/enable=false."
  type        = bool
  default     = true
}

variable "namespace_labels" {
  description = "Extra namespace labels, e.g. istio-injection=enabled."
  type        = map(string)
  default     = {}
}

variable "namespace_annotations" {
  description = "Extra namespace annotations."
  type        = map(string)
  default     = {}
}

variable "values" {
  description = "Chart values as a Terraform object. Encoded to YAML and passed as a values file."
  type        = any
  default     = {}
}

variable "set_values" {
  description = "Individual --set overrides as a flat map. Use for values that must stay strings."
  type        = map(string)
  default     = {}
}

variable "wait" {
  description = "Block until all resources are ready. Turn off for charts whose pods depend on something installed later."
  type        = bool
  default     = true
}

variable "atomic" {
  description = "Roll back automatically if the install or upgrade fails."
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Seconds to wait for the release."
  type        = number
  default     = 600
}
