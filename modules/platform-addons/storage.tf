# Dedicated demo StorageClass. EBS CSI propagates these tag specifications onto
# every dynamically provisioned volume, allowing destroy verification to identify
# exact demo ownership without scanning/deleting unrelated available volumes.
resource "kubernetes_storage_class_v1" "demo" {
  count = var.storage_class == "dash0-gp3" ? 1 : 0

  metadata {
    name = var.storage_class
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type               = "gp3"
    encrypted          = "true"
    tagSpecification_1 = "Project=${lookup(var.tags, "Project", "dash0-lab")}"
    tagSpecification_2 = "Environment=${lookup(var.tags, "Environment", "demo")}"
    tagSpecification_3 = "Purpose=${lookup(var.tags, "Purpose", "dash0-observability-demo")}"
  }
}
