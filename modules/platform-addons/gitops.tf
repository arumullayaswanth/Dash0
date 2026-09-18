###############################################################################
# GitOps and IaC automation
#
# ArgoCD, FluxCD and Atlantis. These coexist without conflict.
#
# Dash0 ships pre-built check rules for ArgoCD sync/health, so this profile is
# the natural place to demo the Integrations Hub.
###############################################################################

module "argocd" {
  source = "../helm-addon"

  enabled = var.gitops.argocd

  release_name  = local.catalog.argocd.release
  repository    = local.catalog.argocd.repository
  chart         = local.catalog.argocd.chart
  chart_version = local.catalog.argocd.version
  namespace     = local.catalog.argocd.namespace

  values = {
    global = {
      # Every ArgoCD component exposes Prometheus metrics; annotating globally is
      # simpler than per-component and the Dash0 collector picks all of them up.
      podAnnotations = {
        "prometheus.io/scrape" = "true"
      }
    }

    # Single replica everywhere. HA on a demo cluster just burns capacity.
    controller = {
      replicas = 1
      metrics = {
        enabled = true
        service = {
          annotations = {
            "prometheus.io/scrape" = "true"
            "prometheus.io/port"   = "8082"
          }
        }
        serviceMonitor = { enabled = var.observability.prometheus_stack }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }

    repoServer = {
      replicas = 1
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = var.observability.prometheus_stack }
      }
      resources = local.medium_resources
    }

    applicationSet = {
      replicas = 1
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = var.observability.prometheus_stack }
      }
    }

    notifications = {
      metrics = {
        enabled = true
      }
    }

    server = {
      replicas = 1
      # insecure=true terminates TLS at the load balancer instead of inside
      # argocd-server. Fine for a demo; do not copy this into production.
      extraArgs = ["--insecure"]
      service = {
        type = "ClusterIP"
      }
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = var.observability.prometheus_stack }
      }
      resources = local.medium_resources
    }

    dex = {
      # No SSO in the demo, so skip Dex entirely.
      enabled = false
    }

    redis = {
      resources = local.medium_resources
    }

    configs = {
      params = {
        "server.insecure" = true
      }
    }
  }

  timeout = 900
}

###############################################################################
# FluxCD
###############################################################################

module "fluxcd" {
  source = "../helm-addon"

  enabled = var.gitops.fluxcd

  release_name  = local.catalog.fluxcd.release
  repository    = local.catalog.fluxcd.repository
  chart         = local.catalog.fluxcd.chart
  chart_version = local.catalog.fluxcd.version
  namespace     = local.catalog.fluxcd.namespace

  values = {
    installCRDs = true

    # Only create a PodMonitor if something owns that CRD. Otherwise the Dash0
    # collector reaches the controllers via the pod annotations below.
    prometheus = {
      podMonitor = {
        create = var.observability.prometheus_stack
      }
    }

    # Flux controllers serve metrics on the http-prom port (8080). Annotating
    # each controller pod is what gets them into Dash0 with no Prometheus server
    # in the path.
    sourceController = {
      create      = true
      annotations = local.flux_scrape_annotations
      resources   = local.medium_resources
    }
    kustomizeController = {
      create      = true
      annotations = local.flux_scrape_annotations
      resources   = local.medium_resources
    }
    helmController = {
      create      = true
      annotations = local.flux_scrape_annotations
      resources   = local.medium_resources
    }
    notificationController = {
      create      = true
      annotations = local.flux_scrape_annotations
      resources   = local.medium_resources
    }

    # Image automation is off by default upstream and not needed for the demo.
    imageAutomationController = { create = false }
    imageReflectionController = { create = false }
  }

  timeout = 900
}

###############################################################################
# Atlantis
#
# Terraform PR automation. Needs a Git provider token to be useful; without one
# it still starts and is fine for showing the workflow shape.
###############################################################################

module "atlantis" {
  source = "../helm-addon"

  enabled = var.gitops.atlantis

  release_name  = local.catalog.atlantis.release
  repository    = local.catalog.atlantis.repository
  chart         = local.catalog.atlantis.chart
  chart_version = local.catalog.atlantis.version
  namespace     = local.catalog.atlantis.namespace

  values = {
    replicaCount = 1

    # Atlantis keeps cloned repos and plan files on disk.
    dataStorage      = local.storage.size
    storageClassName = local.storage.class

    orgAllowlist = var.atlantis_repo_allowlist

    # Only create a ServiceMonitor when something owns that CRD; otherwise the
    # Dash0 collector picks Atlantis up from the pod annotations below.
    servicemonitor = {
      enabled = var.observability.prometheus_stack
    }

    # Atlantis has no built-in auth beyond basic auth; leaving it ClusterIP means
    # it is not reachable from the internet. Port-forward to demo it.
    service = {
      type = "ClusterIP"
    }

    podTemplate = {
      annotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "4141"
        "prometheus.io/path"   = "/metrics"
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "1Gi" }
    }
  }
}
