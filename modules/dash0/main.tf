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

  # Deliberately NOT waiting on the chart's post-install hook job. That job runs
  # `--auto-operator-configuration-resource-available-check`, which only passes
  # once the operator has validated the Dash0 endpoint/token and marked its
  # configuration resource Available. If validation is slow or the token/dataset
  # is wrong, the job exhausts backoffLimit=2 and Helm reports
  # BackoffLimitExceeded, failing the whole apply and destroying the logs.
  #
  # Installing without wait lets Terraform finish; the workflow then waits for
  # the operator Deployment and reads its logs, so a real credential problem is
  # visible instead of an opaque job failure. The hook is disabled via
  # --no-hooks-equivalent below (customResourceDefinitions still install because
  # they are not hooks).
  wait          = false
  wait_for_jobs = false
  timeout       = 900

  # Skip the chart's post-install readiness-check hook. That hook waits for the
  # operator to mark its configuration Available and, on backoffLimit=2, fails
  # the whole apply with an opaque BackoffLimitExceeded that also destroys the
  # logs. The operator itself still installs and reconciles; the workflow waits
  # for the operator Deployment and verifies telemetry afterwards, and the
  # operator logs then show any real credential/dataset error plainly.
  disable_webhooks = true

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
# The operator only deploys its OpenTelemetry collector once at least one
# Dash0Monitoring resource exists. Relying on autoMonitorNamespaces alone proved
# unreliable (it created none, so no collector and no telemetry), so we always
# create explicit Dash0Monitoring resources for the namespaces that matter.
# These namespaces are also created here if missing, so the resource applies
# even before the workload chart runs.
###############################################################################

resource "kubernetes_manifest" "monitoring" {
  for_each = toset(var.monitored_namespaces)

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
