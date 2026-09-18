output "enabled" {
  description = "Whether this addon was installed."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace the addon was installed into."
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name, or null when disabled."
  value       = var.enabled ? helm_release.this[0].name : null
}

output "status" {
  description = "Helm release status. Use as a depends_on anchor."
  value       = var.enabled ? helm_release.this[0].status : null
}
