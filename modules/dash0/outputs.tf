output "namespace" {
  description = "Namespace the Dash0 operator runs in."
  value       = kubernetes_namespace_v1.dash0.metadata[0].name
}

output "secret_name" {
  description = "Name of the Kubernetes Secret holding the Dash0 auth token."
  value       = kubernetes_secret_v1.dash0_auth.metadata[0].name
}

output "chart_version" {
  description = "Installed dash0-operator chart version."
  value       = helm_release.dash0_operator.version
}

output "release_status" {
  description = "Helm release status, useful as a dependency anchor for downstream modules."
  value       = helm_release.dash0_operator.status
}
