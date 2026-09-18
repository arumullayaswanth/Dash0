###############################################################################
# Shared locals
###############################################################################

locals {
  ###########################################################################
  # Dash0 collector endpoint
  #
  # The operator creates this Service at runtime (it is not in the chart).
  # Name is "<release>-opentelemetry-collector-service", ports 4317 gRPC and
  # 4318 HTTP. Verified against the operator source, not guessed.
  #
  # Note the Service uses internalTrafficPolicy: Local, so a pod always reaches
  # the collector DaemonSet instance on its own node. That is intentional and
  # means no cross-AZ hop for telemetry.
  #
  # Workloads that the operator auto-instruments get OTEL_EXPORTER_OTLP_ENDPOINT
  # injected for them. These locals are for the charts that export OTLP
  # themselves and need to be told where to send it (Traefik, Istio, nginx).
  ###########################################################################
  dash0_namespace      = "dash0-system"
  dash0_collector_host = "dash0-operator-opentelemetry-collector-service.${local.dash0_namespace}.svc.cluster.local"
  dash0_collector_grpc = "${local.dash0_collector_host}:4317"
  dash0_collector_http = "http://${local.dash0_collector_host}:4318"

  # The Dash0 collector honours these annotations when prometheusScraping is
  # enabled on a namespace. Applying them to charts that expose a /metrics
  # endpoint is what gets their metrics into Dash0 without a Prometheus in the
  # middle. That distinction is worth showing on camera.
  prometheus_scrape_annotations = {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = "9090"
    "prometheus.io/path"   = "/metrics"
  }

  # Small requests across the board. A demo cluster runs many components at once
  # and unbounded requests mean nothing schedules.
  small_resources = {
    requests = { cpu = "10m", memory = "64Mi" }
  }

  medium_resources = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { memory = "512Mi" }
  }

  # Shared persistence block for the stateful charts.
  storage = {
    class = var.storage_class
    size  = var.data_store_volume_size
  }

  # Which mesh, if any, is active. Used to decide sidecar injection labels.
  active_mesh = var.mesh.istio ? "istio" : (var.mesh.linkerd ? "linkerd" : "none")

  # Flux controllers serve metrics on the port named http-prom, which is 8080.
  flux_scrape_annotations = {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = "8080"
    "prometheus.io/path"   = "/metrics"
  }
}
