###############################################################################
# OpenTelemetry Demo
#
# The traffic source. Without a workload generating spans, Dash0 shows an empty
# cluster and the demo falls flat.
#
# The chart normally bundles its own Collector, Jaeger, Prometheus, Grafana and
# OpenSearch. We turn all of that off and point the services straight at the
# Dash0 operator's collector. That is the whole point: one OTLP endpoint, no
# backend sprawl.
#
# The bundled load generator drives continuous traffic, and the feature flag
# service can inject failures on demand, which is the cleanest way to show error
# detection in Dash0 on camera.
###############################################################################

module "otel_demo" {
  source = "../helm-addon"

  enabled = var.demo_app

  release_name  = local.catalog.otel_demo.release
  repository    = local.catalog.otel_demo.repository
  chart         = local.catalog.otel_demo.chart
  chart_version = local.catalog.otel_demo.version
  namespace     = local.catalog.otel_demo.namespace

  # Explicitly monitored so Dash0 auto-instrumentation applies here.
  monitored = true

  namespace_labels = merge(
    var.mesh.istio ? { "istio-injection" = "enabled" } : {},
  )

  namespace_annotations = merge(
    var.mesh.linkerd ? { "linkerd.io/inject" = "enabled" } : {},
  )

  values = {
    default = {
      # The chart builds every service's endpoint as
      # http://$(OTEL_COLLECTOR_NAME):4318, so overriding this one variable
      # redirects all ~15 services at the Dash0 collector. Verified by rendering
      # the chart rather than assumed.
      envOverrides = [
        {
          name  = "OTEL_COLLECTOR_NAME"
          value = local.dash0_collector_host
        },
        {
          # Dash0 expects cumulative temporality; this is also the chart default,
          # set explicitly so it survives a chart bump.
          name  = "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"
          value = "cumulative"
        },
      ]

    }

    components = {
      # The load generator is what keeps data flowing between takes.
      "load-generator" = {
        enabled = true
        env = [
          {
            # 5 concurrent users populates service maps without saturating a
            # small node group.
            name  = "LOCUST_USERS"
            value = "5"
          },
        ]
      }

      # Flagd drives the deliberate-failure scenarios, which is how you trigger
      # an error on demand while recording.
      flagd = {
        enabled = true
      }
    }

    # eBPF profiling is off by default and would need its own collector.
    "otel-ebpf-profiler" = {
      enabled = false
    }

    # ---- everything below is the bundled backend, all disabled ----

    "opentelemetry-collector" = {
      # The Dash0 operator already runs a collector DaemonSet on every node.
      # Running a second one here would double-count metrics.
      enabled = var.otel_demo_use_own_collector
    }

    jaeger = {
      enabled = false
    }

    prometheus = {
      enabled = false
    }

    grafana = {
      enabled = false
    }

    opensearch = {
      enabled = false
    }
  }

  # Roughly 15 services plus images to pull on cold nodes.
  timeout = 1200
  # Do not roll back the whole release if one service is slow to become ready.
  atomic = false
}

###############################################################################
# Dash0 monitoring for the demo namespace
#
# The Dash0 operator only deploys its collector once a Dash0Monitoring resource
# exists in a namespace. The namespace label alone (dash0.com/enable=true) is
# not sufficient without auto-monitor actually reconciling, which proved
# unreliable. Creating the resource here guarantees the demo namespace is
# monitored and its ~15 services are instrumented and exported to Dash0.
###############################################################################

resource "kubernetes_manifest" "otel_demo_monitoring" {
  count = var.demo_app ? 1 : 0

  manifest = {
    apiVersion = "operator.dash0.com/v1beta1"
    kind       = "Dash0Monitoring"
    metadata = {
      name      = "dash0-monitoring-resource"
      namespace = local.catalog.otel_demo.namespace
    }
    spec = {
      instrumentWorkloads = {
        mode = "all"
      }
      logCollection   = { enabled = true }
      eventCollection = { enabled = true }
      prometheusScraping = {
        enabled = true
      }
    }
  }

  # The namespace and its workloads exist once the demo release is applied.
  depends_on = [module.otel_demo]
}
