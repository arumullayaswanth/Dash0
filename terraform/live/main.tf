###############################################################################
# Root stack
#
# Composes the five modules:
#   network         -> VPC, subnets, NAT
#   eks-cluster     -> control plane, node groups, addons, Karpenter IAM
#   dash0           -> operator, collector, monitoring config
#   platform-addons -> every technology profile
#
# Order matters: Dash0 goes in before the technology profiles so that its
# webhook is live when those workloads are created, which is what lets the
# operator inject instrumentation on first deploy rather than on a later restart.
###############################################################################

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = var.repository_url
      # Makes it obvious in the AWS console that this is disposable.
      Purpose = "dash0-observability-demo"
    },
    var.tags
  )

  # Karpenter needs its discovery tag on subnets and security groups, so the
  # network module has to know at plan time.
  karpenter_enabled = var.enable_karpenter
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  az_count           = var.az_count

  single_nat_gateway = var.single_nat_gateway

  enable_vpc_endpoints       = true
  enable_interface_endpoints = var.enable_interface_endpoints

  karpenter_discovery = local.karpenter_enabled

  tags = local.tags
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  intra_subnet_ids   = module.network.intra_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  cni_mode = var.cni_mode

  node_groups = {
    # One always-on group. Karpenter, when enabled, scales everything else.
    system = {
      min_size     = var.system_node_min
      max_size     = var.system_node_max
      desired_size = var.system_node_desired

      instance_types = var.system_node_instance_types

      labels = merge(
        {
          role = "system"
        },
        # Karpenter refuses to run on nodes it manages, so it is pinned here.
        local.karpenter_enabled ? { "karpenter.sh/controller" = "true" } : {}
      )
    }
  }

  node_disk_size = var.node_disk_size

  enable_ebs_csi_driver = true
  enable_karpenter      = local.karpenter_enabled

  # The CI role creates the cluster, so enable_cluster_creator_admin_permissions
  # in the eks-cluster module already grants it cluster-admin via a
  # "cluster_creator" access entry. Adding it again here produces a duplicate
  # principal and EKS rejects it with ResourceInUseException (409). Extra
  # entries belong here only for principals other than the CI role.
  access_entries = {}

  tags = local.tags
}

###############################################################################
# Dash0
#
# Installed before the technology profiles. The operator's admission webhook has
# to be serving when those workloads are first created, otherwise their pods
# start uninstrumented and only pick up tracing on a later restart.
###############################################################################

module "dash0" {
  source = "../../modules/dash0"

  cluster_name = module.eks_cluster.cluster_name

  otlp_grpc_endpoint = var.dash0_otlp_grpc_endpoint
  api_endpoint       = var.dash0_api_endpoint
  auth_token         = var.dash0_auth_token
  dataset            = var.dash0_dataset

  # Auto-monitor is unreliable on its own (it created no monitoring resources,
  # so the operator deployed no collector). We keep it on AND explicitly monitor
  # known namespaces so a collector is guaranteed. "default" and "kube-system"
  # always exist; the demo app namespace is monitored inside the demo module.
  auto_monitor_namespaces = true
  monitored_namespaces    = ["default", "kube-system"]

  # created-and-updated avoids a cluster-wide pod restart the moment monitoring
  # switches on. Set to "all" if you want existing workloads instrumented
  # immediately and can tolerate the rollout.
  instrument_workloads_mode = var.instrument_workloads_mode

  enable_prometheus_scraping = true
  # The target allocator is only needed once something owns the Prometheus CRDs.
  enable_prometheus_crd_support = var.profile_observability.prometheus_stack

  enable_python_instrumentation = true

  # cluster_ready (not just the cluster) so the caller's EKS access entry has
  # propagated before the first Kubernetes API call. Depending on the cluster
  # alone races the authorizer and fails with "namespaces is forbidden".
  cluster_ready = module.eks_cluster.cluster_ready

  # module.network as well as the cluster: the operator's post-install job needs
  # outbound internet to reach the Dash0 API, which only works once the NAT
  # gateway and its private route exist. Depending on the cluster alone lets Helm
  # start while NAT is still provisioning, and the job exhausts its retries.
  depends_on = [module.eks_cluster, module.network]
}

###############################################################################
# Technology profiles
###############################################################################

module "platform_addons" {
  source = "../../modules/platform-addons"

  cluster_name     = module.eks_cluster.cluster_name
  cluster_endpoint = module.eks_cluster.cluster_endpoint
  region           = var.region

  cni_mode             = var.cni_mode
  cluster_service_cidr = module.eks_cluster.cluster_service_cidr

  karpenter = module.eks_cluster.karpenter

  platform      = var.profile_platform
  mesh          = var.profile_mesh
  ingress       = var.profile_ingress
  gateways      = var.profile_gateways
  gitops        = var.profile_gitops
  data_stores   = var.profile_data_stores
  observability = var.profile_observability

  keep_prometheus_server  = var.keep_prometheus_server
  atlantis_repo_allowlist = var.atlantis_repo_allowlist

  demo_app = var.enable_demo_app

  storage_class          = var.storage_class
  data_store_volume_size = var.data_store_volume_size

  cluster_ready = module.eks_cluster.cluster_ready

  tags = local.tags

  # Charts install into a cluster that is already reporting to Dash0.
  depends_on = [module.dash0]
}

###############################################################################
# Bastion (optional)
#
# A small SSM-managed EC2 jump host with kubectl/helm/aws preinstalled. Connect
# from the AWS Console (EC2 -> Connect -> Session Manager) to inspect the
# cluster and run commands. No SSH key, no public IP, no inbound ports.
###############################################################################

module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../modules/bastion"

  name         = local.name
  cluster_name = module.eks_cluster.cluster_name
  region       = var.region

  vpc_id = module.network.vpc_id
  # First private subnet: has NAT egress for SSM and image pulls.
  subnet_id = module.network.private_subnet_ids[0]

  instance_type   = var.bastion_instance_type
  kubectl_version = var.kubernetes_version

  tags = local.tags
}

# Grant the bastion role cluster access. Defined here rather than inside the
# eks-cluster module to avoid a cycle: the role ARN comes from the bastion
# module, which itself depends on the cluster name.
resource "aws_eks_access_entry" "bastion" {
  count = var.enable_bastion ? 1 : 0

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.bastion[0].iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion" {
  count = var.enable_bastion ? 1 : 0

  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.bastion[0].iam_role_arn
  # Cluster-wide admin so you can inspect everything on camera. Narrow to
  # AmazonEKSClusterViewPolicy if you only need read access.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}
