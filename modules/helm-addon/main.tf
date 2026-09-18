###############################################################################
# helm-addon
#
# One consistent way to install every chart in this repo. Exists so that each
# technology profile is a few lines of config instead of a repeated helm_release
# block, and so behaviour (namespace creation, labels, atomic upgrades) is
# identical everywhere.
#
# The namespace gets the dash0.com/enable label wired to var.monitored, which is
# how a profile opts in or out of Dash0 auto-monitoring.
###############################################################################

locals {
  # Charts published to OCI registries are referenced by full oci:// URL in
  # `chart` with no `repository`, so detect that and split accordingly.
  is_oci = startswith(var.repository, "oci://")

  chart_ref = local.is_oci ? "${var.repository}/${var.chart}" : var.chart
  repo_ref  = local.is_oci ? null : var.repository
  namespace = var.namespace
  create_ns = var.create_namespace && var.enabled
}

resource "kubernetes_namespace_v1" "this" {
  count = local.create_ns ? 1 : 0

  metadata {
    name = local.namespace

    labels = merge(
      {
        "app.kubernetes.io/managed-by" = "terraform"
        # false keeps the namespace out of Dash0 auto-monitoring.
        "dash0.com/enable" = var.monitored ? "true" : "false"
      },
      var.namespace_labels
    )

    annotations = var.namespace_annotations
  }
}

resource "helm_release" "this" {
  count = var.enabled ? 1 : 0

  name       = var.release_name
  repository = local.repo_ref
  chart      = local.chart_ref
  version    = var.chart_version
  namespace  = local.namespace

  # We create namespaces ourselves so we can control the Dash0 label.
  create_namespace = false

  values = length(var.values) > 0 ? [yamlencode(var.values)] : []

  # helm provider v3 takes `set` as a list of objects, not repeated blocks.
  set = [
    for k, v in var.set_values : {
      name  = k
      value = v
    }
  ]

  wait          = var.wait
  wait_for_jobs = var.wait
  timeout       = var.timeout
  # Roll back a failed install instead of leaving a broken half-release that
  # blocks the next apply.
  atomic = var.atomic
  # Some charts (meshes, CRD bundles) need CRDs replaced on upgrade.
  skip_crds = false

  max_history = 5

  depends_on = [kubernetes_namespace_v1.this]
}
