###############################################################################
# Observability, autoscaling and policy
#
# The framing that matters here: Prometheus is not competing with Dash0 in this
# setup. The Dash0 collector scrapes the ServiceMonitors that kube-prometheus-stack
# installs, so you get "keep your existing Prometheus config, change where the
# data lands". That is a stronger segment than a side-by-side comparison.
#
# Requires enable_prometheus_crd_support on the Dash0 module, which deploys the
# OTel target allocator so ServiceMonitor/PodMonitor discovery actually works.
###############################################################################

module "kube_prometheus_stack" {
  source = "../helm-addon"

  enabled = var.observability.prometheus_stack

  release_name  = local.catalog.kube_prometheus_stack.release
  repository    = local.catalog.kube_prometheus_stack.repository
  chart         = local.catalog.kube_prometheus_stack.chart
  chart_version = local.catalog.kube_prometheus_stack.version
  namespace     = local.catalog.kube_prometheus_stack.namespace

  values = {
    # The Prometheus server itself is optional. Keeping it lets you show the
    # before/after; the CRDs and exporters are what the Dash0 collector needs.
    prometheus = {
      enabled = var.keep_prometheus_server

      prometheusSpec = {
        retention = "6h"

        # Pick up ServiceMonitors from every namespace, not just ones carrying
        # the release label. Matches what the Dash0 target allocator does.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        scrapeConfigSelectorNilUsesHelmValues   = false

        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes      = ["ReadWriteOnce"]
              storageClassName = local.storage.class
              resources = {
                requests = {
                  storage = local.storage.size
                }
              }
            }
          }
        }

        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "2Gi" }
        }
      }
    }

    # Grafana stays available so you can contrast it with Dash0 on camera.
    grafana = {
      enabled = var.observability.grafana

      adminPassword = null
      # Chart generates a random admin password into a Secret rather than
      # baking one into Terraform state.
      admin = {
        existingSecret = ""
      }

      service = {
        type = "ClusterIP"
      }

      resources = local.medium_resources

      # Grafana's own metrics.
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "3000"
        "prometheus.io/path"   = "/metrics"
      }
    }

    # Alertmanager off: check rules live in Dash0 for this demo, and Dash0 can
    # forward to an existing Alertmanager if you want that story instead.
    alertmanager = {
      enabled = false
    }

    # These two are the real prize. node-exporter and kube-state-metrics produce
    # the ServiceMonitors that the Dash0 collector scrapes.
    nodeExporter = {
      enabled = true
    }
    "prometheus-node-exporter" = {
      prometheus = {
        monitor = {
          enabled = true
        }
      }
      resources = local.small_resources
    }

    kubeStateMetrics = {
      enabled = true
    }
    "kube-state-metrics" = {
      prometheus = {
        monitor = {
          enabled = true
        }
      }
      resources = local.small_resources
    }

    # EKS does not expose these control plane components to scraping, so the
    # default ServiceMonitors would just produce permanently-down targets.
    kubeApiServer         = { enabled = true }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = var.cni_mode != "cilium" }

    # The operator is needed even when the Prometheus server is disabled, since
    # it owns the ServiceMonitor CRDs.
    prometheusOperator = {
      resources = local.medium_resources
    }
  }

  timeout = 900
}

###############################################################################
# Perses
#
# Dashboards-as-code. The Dash0 operator watches PersesDashboard resources and
# syncs them into Dash0 as real dashboards, which is a genuinely good demo:
# commit a dashboard to Git, watch it appear in Dash0.
###############################################################################

module "perses" {
  source = "../helm-addon"

  enabled = var.observability.perses

  release_name  = local.catalog.perses.release
  repository    = local.catalog.perses.repository
  chart         = local.catalog.perses.chart
  chart_version = local.catalog.perses.version
  namespace     = local.catalog.perses.namespace

  values = {
    replicas = 1
    service = {
      type = "ClusterIP"
    }
    resources = local.medium_resources
  }
}

###############################################################################
# KEDA
#
# Event-driven autoscaling. Pairs naturally with the Kafka or RabbitMQ profile:
# queue depth drives replica count, and both sides are visible in Dash0.
###############################################################################

module "keda" {
  source = "../helm-addon"

  enabled = var.observability.keda

  release_name  = local.catalog.keda.release
  repository    = local.catalog.keda.repository
  chart         = local.catalog.keda.chart
  chart_version = local.catalog.keda.version
  namespace     = local.catalog.keda.namespace

  values = {
    prometheus = {
      metricServer = {
        enabled = true
        podMonitor = {
          enabled = var.observability.prometheus_stack
        }
      }
      operator = {
        enabled = true
        podMonitor = {
          enabled = var.observability.prometheus_stack
        }
      }
    }

    resources = {
      operator = local.medium_resources
    }
  }
}

###############################################################################
# Kyverno
#
# Policy engine. Worth noting on camera: Kyverno is an admission webhook, and
# the Dash0 operator is too. The operator docs call out Kyverno compatibility,
# and the policy below is the usual gotcha - a mutating policy that strips
# init containers would break Dash0's instrumentation injection.
###############################################################################

module "kyverno" {
  source = "../helm-addon"

  enabled = var.observability.kyverno

  release_name  = local.catalog.kyverno.release
  repository    = local.catalog.kyverno.repository
  chart         = local.catalog.kyverno.chart
  chart_version = local.catalog.kyverno.version
  namespace     = local.catalog.kyverno.namespace

  values = {
    # Single replica for admission controller; three is the production default
    # and unnecessary here.
    admissionController = {
      replicas = 1
      container = {
        resources = local.medium_resources
      }
      # Kyverno must not intercept the Dash0 operator's own namespace, or the two
      # webhooks can deadlock during startup.
      podAnnotations = local.prometheus_scrape_annotations
    }

    backgroundController = {
      replicas  = 1
      resources = local.medium_resources
    }

    cleanupController = {
      replicas  = 1
      resources = local.medium_resources
    }

    reportsController = {
      replicas  = 1
      resources = local.medium_resources
    }

    config = {
      # Exclude the operator and kube-system from admission control.
      webhooks = [
        {
          namespaceSelector = {
            matchExpressions = [
              {
                key      = "kubernetes.io/metadata.name"
                operator = "NotIn"
                values   = ["kube-system", local.dash0_namespace]
              }
            ]
          }
        }
      ]
    }
  }

  timeout = 900
}

###############################################################################
# Dapr
###############################################################################

module "dapr" {
  source = "../helm-addon"

  enabled = var.observability.dapr

  release_name  = local.catalog.dapr.release
  repository    = local.catalog.dapr.repository
  chart         = local.catalog.dapr.chart
  chart_version = local.catalog.dapr.version
  namespace     = local.catalog.dapr.namespace

  values = {
    global = {
      # Dapr's sidecars emit OTLP natively.
      logAsJson = true
      ha = {
        enabled = false
      }
      prometheus = {
        enabled = true
        port    = 9090
      }
    }

    dapr_operator = {
      resources = local.medium_resources
    }
    dapr_sidecar_injector = {
      resources = local.medium_resources
    }
    dapr_sentry = {
      resources = local.medium_resources
    }
    dapr_placement = {
      resources = local.medium_resources
    }
  }
}

# Dapr's tracing config points its sidecars at the Dash0 collector.
resource "kubernetes_manifest" "dapr_tracing" {
  count = var.observability.dapr ? 1 : 0

  manifest = {
    apiVersion = "dapr.io/v1alpha1"
    kind       = "Configuration"
    metadata = {
      name      = "dash0-tracing"
      namespace = local.catalog.dapr.namespace
    }
    spec = {
      tracing = {
        # 1 = 100%. Demo only.
        samplingRate = "1"
        otel = {
          endpointAddress = local.dash0_collector_host
          isSecure        = false
          protocol        = "grpc"
        }
      }
      metric = {
        enabled = true
      }
    }
  }

  depends_on = [module.dapr]
}

###############################################################################
# Keycloak
#
# Identity provider. Useful as a "real" Java workload: the Dash0 operator
# auto-instruments it with the OTel Java agent, so you get traces from software
# you did not write and did not modify. That is a strong demo moment.
###############################################################################

module "keycloak" {
  source = "../helm-addon"

  enabled = var.observability.keycloak

  release_name  = local.catalog.keycloak.release
  repository    = local.catalog.keycloak.repository
  chart         = local.catalog.keycloak.chart
  chart_version = local.catalog.keycloak.version
  namespace     = local.catalog.keycloak.namespace

  values = {
    replicas = 1

    # Dev-mode H2 database. Fine for a demo; never for real use.
    command = [
      "/opt/keycloak/bin/kc.sh",
      "start-dev",
    ]

    extraEnv = yamlencode([
      {
        name  = "KEYCLOAK_ADMIN"
        value = "admin"
      },
      {
        # Chart-generated random password would be better, but Keycloak needs it
        # as a plain env var. Left as a well-known value because this instance is
        # ClusterIP-only and never internet-reachable.
        name  = "KEYCLOAK_ADMIN_PASSWORD"
        value = "admin"
      },
      {
        name  = "KC_HEALTH_ENABLED"
        value = "true"
      },
      {
        name  = "KC_METRICS_ENABLED"
        value = "true"
      },
    ])

    service = {
      type = "ClusterIP"
    }

    resources = {
      requests = { cpu = "200m", memory = "512Mi" }
      limits   = { memory = "1Gi" }
    }
  }

  timeout = 900
}
