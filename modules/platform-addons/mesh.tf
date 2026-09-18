###############################################################################
# Networking and service mesh
#
# Cilium (CNI + eBPF), Istio, or Linkerd. The guards enforce one mesh at a time.
###############################################################################

###############################################################################
# Cilium
#
# Only installed when cni_mode = "cilium", which also removes the vpc-cni addon
# in the eks-cluster module. Cilium then owns pod IPs and replaces kube-proxy.
###############################################################################

module "cilium" {
  source = "../helm-addon"

  enabled = var.cni_mode == "cilium"

  release_name  = local.catalog.cilium.release
  repository    = local.catalog.cilium.repository
  chart         = local.catalog.cilium.chart
  chart_version = local.catalog.cilium.version
  namespace     = local.catalog.cilium.namespace
  # kube-system is pre-existing.
  create_namespace = false

  # Built unconditionally; the release is gated by `enabled` above. A conditional
  # with differently-shaped branches is a Terraform type error.
  values = {
    # ENI mode gives pods real VPC IPs, matching what the AWS CNI would do, so
    # security groups and VPC flow logs still make sense.
    eni = {
      enabled = true
    }
    ipam = {
      mode = "eni"
    }
    # Routing directly through the VPC rather than an overlay.
    routingMode = "native"
    # Cilium cannot run alongside the AWS CNI's own masquerading.
    egressMasqueradeInterfaces = ["eth+"]

    # Take over from kube-proxy entirely. This is the headline eBPF story.
    kubeProxyReplacement = "true"
    k8sServiceHost       = replace(coalesce(var.cluster_endpoint, ""), "https://", "")
    k8sServicePort       = 443

    # Required so Cilium can program service routing without kube-proxy.
    k8sClientRateLimit = {
      qps   = 20
      burst = 40
    }

    # Hubble is the observability layer. Its metrics are the interesting part for
    # a Dash0 demo: L7 HTTP and DNS visibility with no application changes.
    hubble = {
      enabled = true
      relay = {
        enabled = true
      }
      ui = {
        # The UI is a nice visual, but Dash0 is the destination for the data.
        enabled = true
      }
      metrics = {
        enabled = [
          "dns:query;ignoreAAAA",
          "drop",
          "tcp",
          "flow",
          "port-distribution",
          "icmp",
          "httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction",
        ]
        # Scraped by the Dash0 collector via the annotations below.
        enableOpenMetrics = true
      }
    }

    operator = {
      # Single replica: a demo cluster does not need operator HA and two
      # replicas on a small node group wastes capacity.
      replicas = 1
      prometheus = {
        enabled = true
      }
    }

    prometheus = {
      enabled = true
    }

    # Cilium's own agent metrics.
    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9962"
    }
  }

  # Nodes are NotReady until Cilium is running, so waiting here would deadlock
  # against the very DaemonSet that makes them Ready.
  wait   = false
  atomic = false
}

###############################################################################
# Istio
#
# Three releases: CRDs (base), control plane (istiod), ingress gateway. They
# share the istio-system namespace, so only the first creates it.
###############################################################################

module "istio_base" {
  source = "../helm-addon"

  enabled = var.mesh.istio

  release_name  = local.catalog.istio_base.release
  repository    = local.catalog.istio_base.repository
  chart         = local.catalog.istio_base.chart
  chart_version = local.catalog.istio_base.version
  namespace     = local.catalog.istio_base.namespace

  values = {
    defaultRevision = "default"
  }
}

module "istiod" {
  source = "../helm-addon"

  enabled = var.mesh.istio

  release_name  = local.catalog.istiod.release
  repository    = local.catalog.istiod.repository
  chart         = local.catalog.istiod.chart
  chart_version = local.catalog.istiod.version
  namespace     = local.catalog.istiod.namespace
  # istio_base already created and labelled the namespace.
  create_namespace = false

  values = {
    meshConfig = {
      # Access logs to stdout means the Dash0 collector's filelog receiver picks
      # them up with no extra wiring. Good demo beat: mesh logs in Dash0 without
      # touching the app.
      accessLogFile = "/dev/stdout"

      # Native OTLP tracing straight to the Dash0 operator's collector service.
      # This is the cleanest way to show mesh spans arriving in Dash0.
      enableTracing = true
      defaultConfig = {
        tracing = {
          # 100% sampling because this is a demo. Never in production.
          sampling = 100.0
        }
      }
      extensionProviders = [
        {
          name = "dash0-otel"
          opentelemetry = {
            service = local.dash0_collector_host
            port    = 4317
          }
        }
      ]
    }

    pilot = {
      # One istiod is enough for a demo and keeps the node group small.
      autoscaleMin = 1
      autoscaleMax = 2
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "15014"
      }
    }

    global = {
      proxy = {
        resources = {
          requests = { cpu = "10m", memory = "64Mi" }
          limits   = { memory = "256Mi" }
        }
      }
    }
  }

  depends_on = [module.istio_base]
}

# Turns on tracing for the mesh, pointing at the extension provider above.
resource "kubernetes_manifest" "istio_telemetry" {
  count = var.mesh.istio ? 1 : 0

  manifest = {
    apiVersion = "telemetry.istio.io/v1"
    kind       = "Telemetry"
    metadata = {
      name      = "mesh-default"
      namespace = local.catalog.istiod.namespace
    }
    spec = {
      tracing = [
        {
          providers = [{ name = "dash0-otel" }]
          # Sampled at the provider; this keeps every trace for the demo.
          randomSamplingPercentage = 100
        }
      ]
    }
  }

  depends_on = [module.istiod]
}

module "istio_gateway" {
  source = "../helm-addon"

  enabled = var.mesh.istio

  release_name  = local.catalog.istio_gateway.release
  repository    = local.catalog.istio_gateway.repository
  chart         = local.catalog.istio_gateway.chart
  chart_version = local.catalog.istio_gateway.version
  namespace     = local.catalog.istio_gateway.namespace

  namespace_labels = {
    # The gateway itself must not get a sidecar.
    "istio-injection" = "disabled"
  }

  values = {
    service = {
      type = "LoadBalancer"
      annotations = {
        # NLB is cheaper and faster to provision than an ALB, and we only need L4
        # in front of Envoy.
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      }
    }
    autoscaling = {
      enabled     = true
      minReplicas = 1
      maxReplicas = 3
    }
    resources = local.medium_resources
  }

  depends_on = [module.istiod]
}

###############################################################################
# Linkerd
#
# Needs cert-manager for its issuer, enforced by the cert_manager_dependency
# guard. Two releases: CRDs then control plane.
###############################################################################

module "linkerd_crds" {
  source = "../helm-addon"

  enabled = var.mesh.linkerd

  release_name  = local.catalog.linkerd_crds.release
  repository    = local.catalog.linkerd_crds.repository
  chart         = local.catalog.linkerd_crds.chart
  chart_version = local.catalog.linkerd_crds.version
  namespace     = local.catalog.linkerd_crds.namespace

  namespace_annotations = {
    # Linkerd requires this on its own namespace.
    "linkerd.io/inject" = "disabled"
  }
}

module "linkerd_control_plane" {
  source = "../helm-addon"

  enabled = var.mesh.linkerd

  release_name     = local.catalog.linkerd_control_plane.release
  repository       = local.catalog.linkerd_control_plane.repository
  chart            = local.catalog.linkerd_control_plane.chart
  chart_version    = local.catalog.linkerd_control_plane.version
  namespace        = local.catalog.linkerd_control_plane.namespace
  create_namespace = false

  # Built unconditionally; gated by `enabled`. try() covers the count=0 case.
  values = {
    # The issuer certificate is supplied as a Secret (see below) rather than
    # letting the chart generate one, so it survives re-applies.
    identity = {
      externalCA = false
      issuer = {
        scheme = "kubernetes.io/tls"
      }
    }

    identityTrustAnchorsPEM = try(tls_self_signed_cert.linkerd_ca[0].cert_pem, "")

    proxy = {
      resources = {
        cpu    = { request = "10m" }
        memory = { request = "32Mi", limit = "256Mi" }
      }
    }

    controllerReplicas = 1

    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "4191"
    }
  }

  depends_on = [
    module.linkerd_crds,
    kubernetes_secret_v1.linkerd_issuer,
  ]
}

###############################################################################
# Linkerd PKI
#
# Linkerd needs a trust anchor plus an intermediate issuer. Generating them in
# Terraform is simpler than the cert-manager bootstrap dance, at the cost of the
# private keys living in state. Acceptable for a demo cluster; use cert-manager
# with a real CA for anything else.
###############################################################################

resource "tls_private_key" "linkerd_ca" {
  count = var.mesh.linkerd ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "linkerd_ca" {
  count = var.mesh.linkerd ? 1 : 0

  private_key_pem = tls_private_key.linkerd_ca[0].private_key_pem

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  is_ca_certificate     = true
  validity_period_hours = 8760
  allowed_uses          = ["cert_signing", "crl_signing"]
}

resource "tls_private_key" "linkerd_issuer" {
  count = var.mesh.linkerd ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "linkerd_issuer" {
  count = var.mesh.linkerd ? 1 : 0

  private_key_pem = tls_private_key.linkerd_issuer[0].private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "linkerd_issuer" {
  count = var.mesh.linkerd ? 1 : 0

  cert_request_pem   = tls_cert_request.linkerd_issuer[0].cert_request_pem
  ca_private_key_pem = tls_private_key.linkerd_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.linkerd_ca[0].cert_pem

  is_ca_certificate     = true
  validity_period_hours = 8760
  allowed_uses          = ["cert_signing", "crl_signing"]
}

resource "kubernetes_secret_v1" "linkerd_issuer" {
  count = var.mesh.linkerd ? 1 : 0

  metadata {
    name      = "linkerd-identity-issuer"
    namespace = local.catalog.linkerd_control_plane.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.linkerd_issuer[0].cert_pem
    "tls.key" = tls_private_key.linkerd_issuer[0].private_key_pem
    "ca.crt"  = tls_self_signed_cert.linkerd_ca[0].cert_pem
  }

  depends_on = [module.linkerd_crds]
}
