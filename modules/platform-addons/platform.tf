###############################################################################
# Baseline platform
#
# cert-manager, metrics-server, Karpenter and the Gateway API CRDs. Installed
# before everything else because other profiles depend on them.
###############################################################################

module "cert_manager" {
  source = "../helm-addon"

  enabled = var.platform.cert_manager

  release_name  = local.catalog.cert_manager.release
  repository    = local.catalog.cert_manager.repository
  chart         = local.catalog.cert_manager.chart
  chart_version = local.catalog.cert_manager.version
  namespace     = local.catalog.cert_manager.namespace

  values = {
    # Chart-managed CRDs keep install and uninstall symmetrical.
    crds = {
      enabled = true
      keep    = false
    }

    # The startupapicheck is a post-install hook Job that calls the cert-manager
    # API to confirm readiness. On a fresh cluster it frequently exhausts its
    # retries before the webhook is routable and fails the release with
    # BackoffLimitExceeded. cert-manager still becomes ready on its own, so this
    # check is disabled; nothing here depends on it passing synchronously.
    startupapicheck = {
      enabled = false
    }

    # cert-manager exposes Prometheus metrics; the annotations are what the Dash0
    # collector looks for when prometheusScraping is on.
    prometheus = {
      enabled = true
      servicemonitor = {
        # Only create a ServiceMonitor if something owns that CRD.
        enabled = var.observability.prometheus_stack
      }
    }

    podAnnotations = local.prometheus_scrape_annotations

    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
    }
  }
}

module "metrics_server" {
  source = "../helm-addon"

  enabled = var.platform.metrics_server

  release_name  = local.catalog.metrics_server.release
  repository    = local.catalog.metrics_server.repository
  chart         = local.catalog.metrics_server.chart
  chart_version = local.catalog.metrics_server.version
  namespace     = local.catalog.metrics_server.namespace
  # kube-system already exists and is not ours to label.
  create_namespace = false

  values = {
    args = [
      # EKS worker node kubelet serving certs are not signed by the cluster CA.
      "--kubelet-insecure-tls",
    ]
    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
    }
  }
}

###############################################################################
# Karpenter
#
# The IAM role, node role, instance profile and interruption queue are created
# by the eks-cluster module. This installs the controller and one NodePool.
###############################################################################

module "karpenter" {
  source = "../helm-addon"

  enabled = var.karpenter != null

  release_name     = local.catalog.karpenter.release
  repository       = local.catalog.karpenter.repository
  chart            = local.catalog.karpenter.chart
  chart_version    = local.catalog.karpenter.version
  namespace        = local.catalog.karpenter.namespace
  create_namespace = false

  # Built unconditionally with try(), because a conditional whose branches have
  # different object shapes is a type error in Terraform. The release itself is
  # gated by `enabled` above, so these values are unused when Karpenter is off.
  values = {
    settings = {
      clusterName     = var.cluster_name
      clusterEndpoint = var.cluster_endpoint
      # Spot interruption and node-termination events arrive here, letting
      # Karpenter drain a node before EC2 reclaims it.
      interruptionQueue = try(var.karpenter.queue_name, "")
    }

    serviceAccount = {
      name = try(var.karpenter.service_account, "karpenter")
      # Pod Identity association is created in the eks-cluster module, so no
      # IRSA annotation is needed here.
      create = true
    }

    # Karpenter must not run on nodes it manages, or it can evict itself and
    # deadlock. The system node group carries this label.
    nodeSelector = {
      "karpenter.sh/controller" = "true"
    }

    controller = {
      resources = {
        requests = { cpu = "200m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  }

  # The controller crash-loops until its CRDs and queue exist; that is fine, but
  # do not block the apply on readiness.
  wait = false
}

###############################################################################
# Karpenter NodePool + EC2NodeClass
#
# Written as raw manifests because they are CRs, not chart values.
###############################################################################

resource "kubernetes_manifest" "karpenter_node_class" {
  count = var.karpenter != null ? 1 : 0

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      # AL2023 matches the managed node group family.
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" }
      ]
      role = var.karpenter.node_iam_role_name

      # Discovery by tag is why the network module tags subnets when
      # karpenter_discovery is on.
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]

      metadataOptions = {
        httpEndpoint = "enabled"
        httpTokens   = "required"
        # Same reason as the managed node groups: pods need to reach IMDS so the
        # OTel resourcedetection processor can fill in cloud.* attributes.
        httpPutResponseHopLimit = 2
      }

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "50Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]

      tags = var.tags
    }
  }

  depends_on = [module.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  count = var.karpenter != null ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              # Spot first: this is a demo cluster, and interruption handling is
              # itself a good thing to show in Dash0.
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["5"]
            },
          ]
          # Nodes are recycled after 12h so the cluster does not drift during a
          # long recording week.
          expireAfter = "12h"
        }
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }

      limits = {
        cpu    = "32"
        memory = "128Gi"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}

###############################################################################
# Gateway API CRDs
#
# Deliberately not installed here. Each Gateway API implementation ships the
# CRDs in its own chart, and the single_gateway_api_owner guard makes sure only
# one of them is enabled at a time. Installing them centrally as well would mean
# two owners for the same CRDs.
#
# See gateways.tf for where the enabled implementation takes ownership.
###############################################################################
