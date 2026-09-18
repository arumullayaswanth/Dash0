###############################################################################
# Conflict guards
#
# These fail `terraform plan` with a readable message instead of letting you
# discover the clash 15 minutes into an apply. Every rule corresponds to a real,
# reproducible breakage.
#
# Implemented as lifecycle preconditions on a terraform_data resource rather than
# `check` blocks. That distinction matters: `check` blocks only emit *warnings*
# and would let a broken combination apply anyway. Preconditions are hard errors.
###############################################################################

locals {
  mesh_count = length([for enabled in [var.mesh.istio, var.mesh.linkerd] : enabled if enabled])

  gateway_api_owner_count = length([
    for enabled in [var.gateways.envoy_gateway, var.gateways.kgateway] : enabled if enabled
  ])

  # cert-manager issues the webhook certificates these three rely on.
  needs_cert_manager = anytrue([
    var.mesh.linkerd,
    var.ingress.emissary,
    var.gateways.kgateway,
  ])

  # Everything here claims a PersistentVolume.
  needs_storage = anytrue([
    var.data_stores.postgres,
    var.data_stores.mysql,
    var.data_stores.rabbitmq,
    var.data_stores.kafka,
    var.data_stores.clickhouse,
    var.data_stores.tigerdata,
    var.observability.prometheus_stack,
  ])
}

resource "terraform_data" "profile_guards" {
  # Recorded so the guards re-evaluate whenever a profile changes.
  input = {
    mesh          = var.mesh
    ingress       = var.ingress
    gateways      = var.gateways
    data_stores   = var.data_stores
    observability = var.observability
    cni_mode      = var.cni_mode
  }

  lifecycle {
    precondition {
      condition = local.mesh_count <= 1
      error_message = join(" ", [
        "Istio and Linkerd are both enabled.",
        "Both inject a sidecar into every pod in their monitored namespaces and",
        "compete for the same iptables rules, so pods end up with two proxies and",
        "broken traffic. Enable one at a time:",
        "profile_mesh = { istio = true } or profile_mesh = { linkerd = true }.",
      ])
    }

    precondition {
      condition = local.gateway_api_owner_count <= 1
      error_message = join(" ", [
        "Envoy Gateway and kgateway are both enabled.",
        "Each ships and owns the Gateway API CRDs, so whichever applies second",
        "either fails outright or silently takes ownership of the other's",
        "resources. Enable one at a time.",
      ])
    }

    precondition {
      condition = var.cni_mode != "cilium" || var.cluster_service_cidr != null
      error_message = join(" ", [
        "cni_mode is \"cilium\" but cluster_service_cidr was not provided.",
        "Cilium's kube-proxy replacement needs the cluster service CIDR.",
        "Pass module.eks_cluster.cluster_service_cidr.",
      ])
    }

    precondition {
      condition = !local.needs_cert_manager || var.platform.cert_manager
      error_message = join(" ", [
        "Linkerd, Emissary or kgateway is enabled but cert_manager is false.",
        "These charts need cert-manager to issue their webhook certificates and",
        "will hang waiting for a Certificate that never becomes Ready.",
        "Set profile_platform = { cert_manager = true }.",
      ])
    }

    precondition {
      condition = !(var.mesh.istio && var.ingress.emissary)
      error_message = join(" ", [
        "Istio and Emissary are both enabled.",
        "Emissary runs its own Envoy and does not expect an Istio sidecar in front",
        "of it; mTLS STRICT breaks Emissary's health checks and it never becomes",
        "Ready. Use the Istio ingress gateway instead, or drop the mesh for this",
        "segment.",
      ])
    }

    precondition {
      condition = !local.needs_storage || var.storage_class != ""
      error_message = join(" ", [
        "A stateful profile is enabled but storage_class is empty.",
        "Postgres, MySQL, RabbitMQ, Kafka, ClickHouse, TigerData and the",
        "Prometheus stack all request PersistentVolumes. Without a valid",
        "StorageClass their pods sit Pending forever with no obvious error.",
      ])
    }

    precondition {
      condition = var.karpenter == null || try(var.karpenter.instance_profile_name, null) != null
      error_message = join(" ", [
        "Karpenter values were supplied but instance_profile_name is missing.",
        "Pass the whole `karpenter` output of the eks-cluster module and make sure",
        "enable_karpenter = true is set there.",
      ])
    }
  }
}
