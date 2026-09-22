###############################################################################
# EKS cluster module
#
# Wraps terraform-aws-modules/eks/aws v21. Adds:
#   - IMDSv2 reachable at hop limit 2, which the OTel resourcedetection processor
#     needs to populate cloud.* resource attributes in Dash0.
#   - Optional Cilium mode, which removes the aws-node DaemonSet so Cilium can
#     own pod networking.
#   - Karpenter IAM/SQS wiring via the module's own karpenter submodule.
###############################################################################

locals {
  # Cilium replaces the VPC CNI entirely. Installing vpc-cni alongside it means
  # two things racing to configure pod ENIs, so we drop the addon in that mode.
  # The system node group still needs *some* CNI to become Ready, which is why
  # Cilium mode requires the Helm release to land quickly after cluster create.
  core_addons = merge(
    {
      coredns = {
        # CoreDNS cannot schedule until nodes exist, so defer it.
        before_compute = false
      }
      kube-proxy = {}
      eks-pod-identity-agent = {
        before_compute = true
      }
    },
    var.cni_mode == "cilium" ? {} : {
      vpc-cni = {
        before_compute = true
        configuration_values = jsonencode({
          env = {
            # Prefix delegation packs many more pod IPs onto each ENI, which
            # matters once meshes add a sidecar per pod.
            ENABLE_PREFIX_DELEGATION = "true"
            WARM_PREFIX_TARGET       = "1"
          }
        })
      }
    },
    var.enable_ebs_csi_driver ? {
      aws-ebs-csi-driver = {
        service_account_role_arn = module.ebs_csi_irsa[0].arn
      }
    } : {}
  )

  # v21 of the upstream module dropped `eks_managed_node_group_defaults`, so the
  # shared settings are merged into each node group explicitly below.
  node_group_defaults = {
    ami_type       = var.node_ami_type
    instance_types = var.node_instance_types

    iam_role_additional_policies = {
      # Required for SSM session access to nodes when debugging on camera.
      AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    metadata_options = {
      http_endpoint = "enabled"
      # IMDSv2 only.
      http_tokens = "required"
      # Hop limit 2 lets a *pod* reach IMDS through the node's network namespace.
      # Without this the OTel resourcedetection processor cannot read instance
      # metadata and Dash0 shows telemetry with no cloud.* attributes.
      http_put_response_hop_limit = 2
    }

    block_device_mappings = {
      root = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = var.node_disk_size
          volume_type           = "gp3"
          encrypted             = true
          delete_on_termination = true
        }
      }
    }
  }

  # Per-group overrides win over the shared defaults.
  node_groups = {
    for name, cfg in var.node_groups : name => merge(local.node_group_defaults, cfg)
  }
}

data "aws_partition" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.25"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id = var.vpc_id
  # Nodes go in private subnets.
  subnet_ids = var.private_subnet_ids
  # Control plane ENIs go in the no-egress intra subnets.
  control_plane_subnet_ids = var.intra_subnet_ids

  endpoint_public_access = var.endpoint_public_access
  # Restrict who can reach the API server. Defaulting to 0.0.0.0/0 is convenient
  # but means the public endpoint is world-reachable; see variables.tf.
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  endpoint_private_access      = true

  # Control plane logs. Each enabled type bills CloudWatch ingest, so the
  # default keeps it to the two that matter for debugging RBAC and admission.
  enabled_log_types                      = var.enabled_log_types
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # API-only auth. ConfigMap-based aws-auth is legacy.
  authentication_mode = "API"
  # Whoever runs terraform apply gets cluster-admin, otherwise the first kubectl
  # call after create fails and the Helm releases in this run cannot proceed.
  enable_cluster_creator_admin_permissions = true

  addons = local.core_addons

  eks_managed_node_groups = local.node_groups

  # Extra rules so mesh/gateway webhooks on non-standard ports can be reached by
  # the control plane. Without these, admission webhook calls time out.
  node_security_group_additional_rules = merge(
    {
      ingress_self_all = {
        description = "Node to node, all ports"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        type        = "ingress"
        self        = true
      }
      ingress_cluster_webhooks = {
        description                   = "Control plane to webhook ports"
        protocol                      = "tcp"
        from_port                     = 8443
        to_port                       = 9443
        type                          = "ingress"
        source_cluster_security_group = true
      }
      ingress_cluster_webhook_15017 = {
        description                   = "Control plane to Istio sidecar injector"
        protocol                      = "tcp"
        from_port                     = 15017
        to_port                       = 15017
        type                          = "ingress"
        source_cluster_security_group = true
      }
    },
    var.cni_mode == "cilium" ? {
      ingress_cilium_vxlan = {
        description = "Cilium VXLAN overlay"
        protocol    = "udp"
        from_port   = 8472
        to_port     = 8472
        type        = "ingress"
        self        = true
      }
      ingress_cilium_health = {
        description = "Cilium health checks"
        protocol    = "tcp"
        from_port   = 4240
        to_port     = 4240
        type        = "ingress"
        self        = true
      }
    } : {},
    var.node_security_group_additional_rules
  )

  # Additional principals granted cluster access, e.g. the CI role.
  access_entries = var.access_entries

  tags = var.tags
}

###############################################################################
# EBS CSI driver IRSA role
#
# Needed by any profile that uses a PersistentVolumeClaim (Postgres, Kafka,
# ClickHouse, Prometheus). Without it PVCs stay Pending forever.
###############################################################################

module "ebs_csi_irsa" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                  = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

###############################################################################
# Karpenter supporting AWS resources
#
# This creates the IAM role, node role, instance profile and the SQS queue that
# receives spot interruption notices. The Helm release itself lives in the
# platform module so that all chart installs are in one place.
###############################################################################

module "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.25"

  cluster_name = module.eks.cluster_name

  # Pod Identity is simpler than IRSA: no OIDC audience juggling.
  create_pod_identity_association = true
  enable_spot_termination         = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

###############################################################################
# Access propagation gate
#
# EKS access entries are not effective the instant CreateAccessEntry returns;
# the authorizer needs a few seconds to pick them up. Without this wait, the
# first Kubernetes API call in the same apply fails with
# "namespaces is forbidden: User ... cannot create resource".
#
# Downstream modules depend on the cluster_ready output rather than on the
# cluster itself, so Kubernetes and Helm resources are only created once the
# caller's admin access is actually usable.
###############################################################################

resource "time_sleep" "access_propagation" {
  create_duration = "30s"

  triggers = {
    cluster_name = module.eks.cluster_name
  }

  # depends_on covers the whole module, including every access entry and policy
  # association it creates.
  depends_on = [module.eks]
}
