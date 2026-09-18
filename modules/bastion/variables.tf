variable "name" {
  description = "Name prefix for the bastion and its IAM/security resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the bastion should be able to reach with kubectl."
  type        = string
}

variable "region" {
  description = "AWS region, baked into the kubeconfig helper on the bastion."
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the bastion in."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the bastion. It reaches AWS via the NAT gateway and is accessed through SSM, so no public IP is needed."
  type        = string
}

variable "instance_type" {
  description = "Bastion instance type. A small burstable type is plenty for kubectl/helm."
  type        = string
  default     = "t3.small"
}

variable "kubectl_version" {
  description = "kubectl minor version stream to install, matching the cluster."
  type        = string
  default     = "1.34"
}

variable "tags" {
  description = "Tags applied to bastion resources."
  type        = map(string)
  default     = {}
}
