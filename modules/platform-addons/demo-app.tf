###############################################################################
# OpenTelemetry Demo
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

      # When expose_demo_frontend is on, publish the storefront through a public
      # LoadBalancer so it is reachable in a browser. A plain type=LoadBalancer
      # (no annotations) uses the in-tree AWS provider and provisions a public
      # Classic ELB with no AWS Load Balancer Controller required. When off, the
      # chart default (ClusterIP) is kept and access is via port-forward.
      "frontend-proxy" = var.expose_demo_frontend ? {
        service = {
          type = "LoadBalancer"
        }
      } : {}
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

# Read the public load balancer hostname assigned to the frontend-proxy service
# so it can be surfaced as an output. Only read when the service is exposed.
data "kubernetes_service_v1" "demo_frontend" {
  count = var.demo_app && var.expose_demo_frontend ? 1 : 0

  metadata {
    name      = "frontend-proxy"
    namespace = local.catalog.otel_demo.namespace
  }

  depends_on = [module.otel_demo]
}

###############################################################################
# Dash0 monitoring for the demo namespace
#
# No explicit Dash0Monitoring resource is created here. The otel-demo namespace
# is labelled dash0.com/enable=true (monitored = true above), so the Dash0
# operator's auto-monitoring (enabled on the Dash0OperatorConfiguration) manages
# it automatically. Adding an explicit resource on top is rejected by the
# operator webhook ("namespace is automatically managed"). The demo workloads
# are deployed fresh, so created-and-updated instrumentation covers them.
###############################################################################
