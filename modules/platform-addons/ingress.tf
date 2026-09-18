###############################################################################
# Ingress controllers
#
# Each enabled controller provisions its own AWS load balancer, so enabling
# several is billable but functional. They differ in Ingress class, so they can
# coexist; the reason to enable one at a time is cost and clarity on camera.
###############################################################################

locals {
  # Shared NLB annotations. An NLB is quicker to provision than an ALB and we
  # only need L4 in front of these proxies.
  nlb_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"                              = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
  }
}

###############################################################################
# Traefik
###############################################################################

module "traefik" {
  source = "../helm-addon"

  enabled = var.ingress.traefik

  release_name  = local.catalog.traefik.release
  repository    = local.catalog.traefik.repository
  chart         = local.catalog.traefik.chart
  chart_version = local.catalog.traefik.version
  namespace     = local.catalog.traefik.namespace

  values = {
    deployment = {
      replicas = 1
    }

    service = {
      type        = "LoadBalancer"
      annotations = local.nlb_annotations
    }

    # Traefik emits OTLP natively, so it can talk to the Dash0 collector without
    # a Prometheus hop. This is the strongest ingress segment for a Dash0 demo:
    # metrics, traces and access logs all over OTLP.
    metrics = {
      prometheus = {
        # Disable the Prometheus endpoint so OTLP is unambiguously the path.
        service = { enabled = false }
      }
      otlp = {
        enabled = true
        grpc = {
          enabled  = true
          endpoint = local.dash0_collector_grpc
          insecure = true
        }
        addEntryPointsLabels = true
        addRoutersLabels     = true
        addServicesLabels    = true
      }
    }

    tracing = {
      otlp = {
        enabled = true
        grpc = {
          enabled  = true
          endpoint = local.dash0_collector_grpc
          insecure = true
        }
      }
      # Full sampling for the demo.
      sampleRate = 1.0
    }

    logs = {
      general = { level = "INFO" }
      access = {
        # stdout so the Dash0 filelog receiver picks them up.
        enabled = true
        format  = "json"
      }
    }

    # Traefik can act as a Gateway API implementation too, but we leave that to
    # the dedicated gateway profiles so CRD ownership stays with one chart.
    providers = {
      kubernetesGateway = { enabled = false }
      kubernetesIngress = { enabled = true }
      kubernetesCRD     = { enabled = true }
    }

    resources = local.medium_resources
  }
}

###############################################################################
# ingress-nginx
###############################################################################

module "ingress_nginx" {
  source = "../helm-addon"

  enabled = var.ingress.ingress_nginx

  release_name  = local.catalog.ingress_nginx.release
  repository    = local.catalog.ingress_nginx.repository
  chart         = local.catalog.ingress_nginx.chart
  chart_version = local.catalog.ingress_nginx.version
  namespace     = local.catalog.ingress_nginx.namespace

  values = {
    controller = {
      replicaCount = 1

      service = {
        type        = "LoadBalancer"
        annotations = local.nlb_annotations
      }

      # Prometheus-format metrics, scraped by the Dash0 collector via the pod
      # annotations. No Prometheus server required.
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = var.observability.prometheus_stack
        }
      }

      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "10254"
      }

      config = {
        # JSON access logs are far easier to query once they land in Dash0.
        log-format-escape-json = "true"
        log-format-upstream    = "{\"time\":\"$time_iso8601\",\"remote_addr\":\"$remote_addr\",\"request_method\":\"$request_method\",\"request_uri\":\"$request_uri\",\"status\":$status,\"request_time\":$request_time,\"upstream_addr\":\"$upstream_addr\",\"upstream_status\":\"$upstream_status\",\"trace_id\":\"$opentelemetry_trace_id\",\"span_id\":\"$opentelemetry_span_id\"}"

        # Correlates the access log line above with the trace in Dash0.
        enable-opentelemetry = "true"
        otlp-collector-host  = local.dash0_collector_host
        otlp-collector-port  = "4317"
        otel-service-name    = "ingress-nginx"
        otel-sampler         = "AlwaysOn"
      }

      # Ships the OTel module for nginx.
      opentelemetry = {
        enabled = true
      }

      resources = local.medium_resources
    }
  }
}

###############################################################################
# Contour
###############################################################################

module "contour" {
  source = "../helm-addon"

  enabled = var.ingress.contour

  release_name  = local.catalog.contour.release
  repository    = local.catalog.contour.repository
  chart         = local.catalog.contour.chart
  chart_version = local.catalog.contour.version
  namespace     = local.catalog.contour.namespace

  values = {
    contour = {
      replicaCount = 1
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8000"
      }
      resources = local.medium_resources
    }

    envoy = {
      service = {
        type        = "LoadBalancer"
        annotations = local.nlb_annotations
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8002"
      }
    }
  }
}

###############################################################################
# Emissary-ingress
#
# Needs cert-manager, enforced by the cert_manager_dependency guard.
###############################################################################

module "emissary" {
  source = "../helm-addon"

  enabled = var.ingress.emissary

  release_name  = local.catalog.emissary.release
  repository    = local.catalog.emissary.repository
  chart         = local.catalog.emissary.chart
  chart_version = local.catalog.emissary.version
  namespace     = local.catalog.emissary.namespace

  values = {
    replicaCount = 1

    service = {
      type        = "LoadBalancer"
      annotations = local.nlb_annotations
    }

    metrics = {
      serviceMonitor = {
        enabled = var.observability.prometheus_stack
      }
    }

    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8877"
    }

    resources = local.medium_resources
  }

  # Emissary's CRDs and webhook take a while to settle.
  timeout = 900
}

###############################################################################
# HAProxy
###############################################################################

module "haproxy" {
  source = "../helm-addon"

  enabled = var.ingress.haproxy

  release_name  = local.catalog.haproxy.release
  repository    = local.catalog.haproxy.repository
  chart         = local.catalog.haproxy.chart
  chart_version = local.catalog.haproxy.version
  namespace     = local.catalog.haproxy.namespace

  values = {
    controller = {
      replicaCount = 1

      service = {
        type        = "LoadBalancer"
        annotations = local.nlb_annotations
      }

      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "1024"
      }

      resources = local.medium_resources
    }
  }
}
