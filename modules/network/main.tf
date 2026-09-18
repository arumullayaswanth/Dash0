###############################################################################
# Network module
#
# Thin wrapper over terraform-aws-modules/vpc/aws that applies the subnet
# tagging EKS needs for load balancer discovery, and keeps NAT cost tunable.
###############################################################################

locals {
  # Three AZs gives us a realistic multi-AZ story without tripling NAT cost
  # (single_nat_gateway handles that separately).
  azs = slice(var.availability_zones, 0, var.az_count)

  # /19 private subnets leave plenty of pod IP space for the VPC CNI, which
  # assigns real VPC IPs to every pod.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 6, i + 48)]
  intra_subnets   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 6, i + 52)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  # Intra subnets have no route to the internet. The EKS control plane ENIs live
  # here so they cannot egress, which is what we want.
  intra_subnets = local.intra_subnets

  enable_nat_gateway = true
  # One NAT gateway is a deliberate cost tradeoff for a demo cluster: it is a
  # single-AZ failure point but saves ~$65/month per additional AZ.
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required for internal load balancers created by ingress controllers.
  private_subnet_tags = merge(
    {
      "kubernetes.io/role/internal-elb" = "1"
    },
    var.karpenter_discovery ? {
      "karpenter.sh/discovery" = var.name
    } : {},
    var.private_subnet_tags
  )

  public_subnet_tags = merge(
    {
      "kubernetes.io/role/elb" = "1"
    },
    var.public_subnet_tags
  )

  tags = var.tags
}

###############################################################################
# VPC endpoints
#
# Keeps image pulls and API traffic off the NAT gateway. On a demo cluster that
# is mostly a data-transfer cost saving, but it also removes NAT as a hard
# dependency for the kubelet talking to ECR.
###############################################################################

module "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  vpc_id = module.vpc.vpc_id

  # Gateway endpoint: free, and S3 is where ECR stores layers.
  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.intra_route_table_ids)
        tags            = { Name = "${var.name}-s3" }
      }
    },
    # Interface endpoints are billed hourly per AZ, so they are opt-in.
    var.enable_interface_endpoints ? {
      ecr_api = {
        service             = "ecr.api"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        tags                = { Name = "${var.name}-ecr-api" }
      }
      ecr_dkr = {
        service             = "ecr.dkr"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        tags                = { Name = "${var.name}-ecr-dkr" }
      }
      sts = {
        service             = "sts"
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        tags                = { Name = "${var.name}-sts" }
      }
    } : {}
  )

  create_security_group      = true
  security_group_name_prefix = "${var.name}-vpce-"
  security_group_description = "Managed by Terraform. Allows HTTPS from within the VPC to interface endpoints."
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC CIDR"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  tags = var.tags
}
