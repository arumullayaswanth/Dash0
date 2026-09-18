output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs. Worker nodes and pods live here."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Internet-facing load balancers live here."
  value       = module.vpc.public_subnets
}

output "intra_subnet_ids" {
  description = "Intra (no-egress) subnet IDs, used for EKS control plane ENIs."
  value       = module.vpc.intra_subnets
}

output "azs" {
  description = "Availability zones actually in use."
  value       = local.azs
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways. Useful for allowlisting cluster egress."
  value       = module.vpc.nat_public_ips
}
