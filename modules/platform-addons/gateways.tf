###############################################################################
# Gateway API implementations
#
# Envoy Gateway and kgateway each ship and own the Gateway API CRDs, so the
# single_gateway_api_owner guard allows only one at a time. agentgateway is an
# AI/LLM traffic gateway and is additive.
###############################################################################

###############################################################################
# Envoy Gateway
###############################################################################

module "envoy_gateway" {
  source = "../helm-addon"

  enabled = var.gateways.envoy_gateway

  release_name  = local.catalog.envoy_gateway.release
  repository    = local.catalog.envoy_gateway.repository
  chart         = local.catalog.envoy_gateway.chart
  chart_version = local.catalog.envoy_gateway.version
  namespace     = local.catalog.envoy_gateway.namespace

  values = {
    deployment = {
      replicas = 1
      envoyGateway = {
        resources = local.medium_resources
      }
    }

    config = {
      envoyGateway = {
        # Envoy Gateway can emit its own telemetry over OTLP. Sending it to the
        # Dash0 collector rather than scraping keeps the pipeline OTLP-native.
        telemetry = {
          metrics = {
            sinks = [
              {
                type = "OpenTelemetry"
                openTelemetry = {
                  host     = local.dash0_collector_host
                  port     = 4317
                  protocol = "grpc"
                }
              }
            ]
          }
        }
      }
    }
  }

  # CRD install plus webhook readiness takes longer than the default.
  timeout = 900
}

# Tells Envoy Gateway to add OTLP access logging and tracing to every proxy it
# manages. Without this the data plane stays silent even though the control
# plane reports metrics.
resource "kubernetes_manifest" "envoy_proxy_telemetry" {
  count = var.gateways.envoy_gateway ? 1 : 0

  manifest = {
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "EnvoyProxy"
    metadata = {
      name      = "dash0-telemetry"
      namespace = local.catalog.envoy_gateway.namespace
    }
    spec = {
      telemetry = {
        accessLog = {
          settings = [
            {
              sinks = [
                {
                  type = "OpenTelemetry"
                  openTelemetry = {
                    host = local.dash0_collector_host
                    port = 4317
                  }
                }
              ]
            }
          ]
        }
        tracing = {
          # 100% for the demo.
          samplingRate = 100
          provider = {
            type = "OpenTelemetry"
            host = local.dash0_collector_host
            port = 4317
          }
        }
        metrics = {
          prometheus = {
            disable = false
          }
        }
      }
    }
  }

  depends_on = [module.envoy_gateway]
}

###############################################################################
# kgateway
#
# Two releases: CRDs first, then the controller.
###############################################################################

module "kgateway_crds" {
  source = "../helm-addon"

  enabled = var.gateways.kgateway

  release_name  = local.catalog.kgateway_crds.release
  repository    = local.catalog.kgateway_crds.repository
  chart         = local.catalog.kgateway_crds.chart
  chart_version = local.catalog.kgateway_crds.version
  namespace     = local.catalog.kgateway_crds.namespace
}

module "kgateway" {
  source = "../helm-addon"

  enabled = var.gateways.kgateway

  release_name     = local.catalog.kgateway.release
  repository       = local.catalog.kgateway.repository
  chart            = local.catalog.kgateway.chart
  chart_version    = local.catalog.kgateway.version
  namespace        = local.catalog.kgateway.namespace
  create_namespace = false

  values = {
    controller = {
      replicaCount = 1
      resources    = local.medium_resources
    }
  }

  depends_on = [module.kgateway_crds]
}

###############################################################################
# agentgateway
#
# LLM/agent traffic gateway. Interesting alongside Dash0's AI Coding Insights
# angle: it is the runtime counterpart to tracking AI spend.
###############################################################################

module "agentgateway" {
  source = "../helm-addon"

  enabled = var.gateways.agentgateway

  release_name  = local.catalog.agentgateway.release
  repository    = local.catalog.agentgateway.repository
  chart         = local.catalog.agentgateway.chart
  chart_version = local.catalog.agentgateway.version
  namespace     = local.catalog.agentgateway.namespace

  values = {
    replicaCount = 1
    resources    = local.medium_resources

    # agentgateway speaks OTLP for traces and metrics.
    env = {
      OTEL_EXPORTER_OTLP_ENDPOINT = local.dash0_collector_http
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
      OTEL_SERVICE_NAME           = "agentgateway"
    }
  }
}
