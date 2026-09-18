variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the control plane, e.g. \"1.34\"."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC to create the cluster in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for worker nodes."
  type        = list(string)
}

variable "intra_subnet_ids" {
  description = "No-egress subnets for the EKS control plane ENIs."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API server publicly. Needed for GitHub Actions runners and a laptop outside the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API endpoint.
    Leaving this at 0.0.0.0/0 means the API server is reachable from anywhere on
    the internet; it is still authenticated, but narrowing this to your own IP
    plus the CI egress range is strongly preferred.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_log_types" {
  description = "Control plane log types to ship to CloudWatch. Each one bills ingest."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs."
  type        = number
  default     = 7
}

variable "cni_mode" {
  description = <<-EOT
    Pod networking implementation.
      "vpc-cni" - the AWS VPC CNI addon (default, recommended).
      "cilium"  - drop the vpc-cni addon so Cilium can own pod networking.
    Switching this on an existing cluster is disruptive: it changes how every
    pod gets an IP. Recreate the cluster instead.
  EOT
  type        = string
  default     = "vpc-cni"

  validation {
    condition     = contains(["vpc-cni", "cilium"], var.cni_mode)
    error_message = "cni_mode must be either \"vpc-cni\" or \"cilium\"."
  }
}

variable "node_groups" {
  description = "Map of EKS managed node group definitions, passed through to the upstream module."
  type        = any
  default     = {}
}

variable "node_ami_type" {
  description = "AMI type for managed node groups. AL2023 is the current default family."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_instance_types" {
  description = "Default instance types for node groups that do not override it."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for worker nodes. Container images for a full mesh plus data stores need headroom."
  type        = number
  default     = 50
}

variable "enable_ebs_csi_driver" {
  description = "Install the EBS CSI driver addon and its IAM role. Required for any profile using PersistentVolumeClaims."
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Create Karpenter's IAM role, node role, instance profile and spot interruption queue."
  type        = bool
  default     = false
}

variable "node_security_group_additional_rules" {
  description = "Extra node security group rules merged with the module defaults."
  type        = any
  default     = {}
}

variable "access_entries" {
  description = "Additional EKS access entries, e.g. granting the CI role cluster-admin."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
