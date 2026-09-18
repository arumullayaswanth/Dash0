variable "name" {
  description = "Name prefix for the VPC and its resources. Also used as the Karpenter discovery tag value."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be large enough for VPC-CNI pod IPs (/16 recommended)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 18
    error_message = "vpc_cidr must be a valid CIDR of /18 or larger to leave room for pod IP addresses."
  }
}

variable "availability_zones" {
  description = "Ordered list of availability zones to draw from. Pass the output of the aws_availability_zones data source."
  type        = list(string)
}

variable "az_count" {
  description = "How many availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4. EKS requires subnets in at least two AZs."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single-AZ dependency. Recommended for demo clusters."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create the free S3 gateway endpoint so ECR image layers bypass the NAT gateway."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Also create billed interface endpoints (ECR API/DKR, STS). Adds roughly $0.01/hour per endpoint per AZ."
  type        = bool
  default     = false
}

variable "karpenter_discovery" {
  description = "Tag private subnets with karpenter.sh/discovery so Karpenter can find them."
  type        = bool
  default     = false
}

variable "private_subnet_tags" {
  description = "Extra tags merged onto private subnets."
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Extra tags merged onto public subnets."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
