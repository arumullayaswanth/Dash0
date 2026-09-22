###############################################################################
# Dash0 module
#
# Installs the Dash0 operator, which deploys an OpenTelemetry collector into the
# cluster and ships traces, metrics, logs and Kubernetes events to Dash0.
#
# The auth token is written to a Kubernetes Secret and referenced via secretRef.
# The alternative (operator.dash0Export.token) renders the token verbatim into a
# ConfigMap, readable by anyone with cluster API access.
###############################################################################

locals {
  namespace   = "dash0-system"
  secret_name = "dash0-authorization-secret"
  secret_key  = "token"
}

resource "kubernetes_namespace_v1" "dash0" {
  metadata {
    name = local.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      # Keep the operator's own namespace out of auto-monitoring; the operator
      # has dedicated self-monitoring and this avoids a telemetry feedback loop.
      "dash0.com/enable" = "false"
    }
  }
}

resource "kubernetes_secret_v1" "dash0_auth" {
  metadata {
    name      = local.secret_name
    namespace = kubernetes_namespace_v1.dash0.metadata[0].name
  }

  data = {
    (local.secret_key) = var.auth_token
  }

  type = "Opaque"
}

###############################################################################
# Operator
###############################################################################

resource "helm_release" "dash0_operator" {
  name       = "dash0-operator"
  repository = "https://dash0hq.github.io/dash0-operator"
  chart      = "dash0-operator"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.dash0.metadata[0].name

  # The operator's webhook must be serving before any monitoring resource is
  # applied, otherwise workload instrumentation silently no-ops.
  wait          = true
  wait_for_jobs = true
  timeout       = 900

  # atomic=false on purpose. With atomic=true a failed post-install job causes
  # Helm to uninstall the release immediately, which deletes the job and its pod
  # logs and leaves nothing to diagnose. Keeping the failed release lets you run
  #   kubectl -n dash0-system logs job/dash0-operator-post-install
  # to see why it failed. Re-running apply upgrades the release in place.
  atomic          = false
  cleanup_on_fail = false

  # A previous failed install leaves the release in the cluster while Terraform
  # holds nothing in state, so a plain install fails with "cannot re-use a name
  # that is still in use". replace lets Helm take over that existing release
  # rather than requiring a manual `helm uninstall` between attempts.
  replace = true

  values = [yamlencode({
    operator = {
      dash0Export = {
        enabled     = true
        endpoint    = var.otlp_grpc_endpoint
        apiEndpoint = var.api_endpoint
        dataset     = var.dataset

        secretRef = {
          name = kubernetes_secret_v1.dash0_auth.metadata[0].name
          key  = local.secret_key
        }
      }

      # Shows up as k8s.cluster.name on every signal, which is what lets you
      # filter one cluster out of many in the Dash0 UI.
      clusterName = var.cluster_name

      # Node, pod and container metrics that are not namespace scoped.
      kubernetesInfrastructureMetricsCollectionEnabled = true

      # Pod labels and annotations become resource attributes. Useful for
      # grouping by team/owner labels in Dash0.
      collectPodLabelsAndAnnotationsEnabled = true

      # Lets the collector scrape ServiceMonitor / PodMonitor / ScrapeConfig
      # resources. Required for the Prometheus profile to reach Dash0.
      prometheusCrdSupportEnabled = var.enable_prometheus_crd_support

      instrumentation = {
        # Python auto-instrumentation is opt-in upstream.
        enablePythonAutoInstrumentation = var.enable_python_instrumentation
      }

      # Monitor every namespace unless it carries dash0.com/enable=false.
      # This is what makes newly added profiles observable with no extra step.
      autoMonitorNamespaces = {
        enabled       = var.auto_monitor_namespaces
        labelSelector = "dash0.com/enable!=false"
      }

      monitoringTemplate = {
        spec = {
          instrumentWorkloads = {
            # "created-and-updated" avoids restarting every existing pod the
            # moment monitoring switches on. Workloads pick up instrumentation
            # on their next deploy. Use "all" if you want immediate coverage and
            # can tolerate a rolling restart.
            mode = var.instrument_workloads_mode
          }
          logCollection = {
            enabled = true
          }
          eventCollection = {
            enabled = true
          }
          prometheusScraping = {
            enabled = var.enable_prometheus_scraping
          }
          # Sync Perses dashboards and Prometheus rules found in-cluster up to
          # Dash0 as real dashboards and check rules.
          synchronizePersesDashboards = true
          synchronizePrometheusRules  = true
        }
      }
    }
  })]

  depends_on = [kubernetes_secret_v1.dash0_auth]
}

###############################################################################
# Explicit per-namespace monitoring
#
# Only needed for namespaces that opted out of auto-monitoring, or when
# auto_monitor_namespaces is false. Uses the raw manifest resource because the
# CRD is installed by the Helm release above.
###############################################################################

resource "kubernetes_manifest" "monitoring" {
  for_each = var.auto_monitor_namespaces ? toset([]) : toset(var.monitored_namespaces)

  manifest = {
    apiVersion = "operator.dash0.com/v1beta1"
    kind       = "Dash0Monitoring"
    metadata = {
      name      = "dash0-monitoring-resource"
      namespace = each.value
    }
    spec = {
      instrumentWorkloads = {
        mode = var.instrument_workloads_mode
      }
      logCollection   = { enabled = true }
      eventCollection = { enabled = true }
      prometheusScraping = {
        enabled = var.enable_prometheus_scraping
      }
    }
  }

  depends_on = [helm_release.dash0_operator]
}
