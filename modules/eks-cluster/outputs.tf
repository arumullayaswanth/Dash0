output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA cert for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version actually running on the control plane."
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the control plane."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID shared by worker nodes."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, for IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "cluster_service_cidr" {
  description = "Service CIDR of the cluster. Cilium needs this for kube-proxy replacement."
  value       = module.eks.cluster_service_cidr
}

output "karpenter" {
  description = "Karpenter IAM/SQS values needed by the Helm release. Null when Karpenter is disabled."
  value = var.enable_karpenter ? {
    service_account       = module.karpenter[0].service_account
    iam_role_arn          = module.karpenter[0].iam_role_arn
    node_iam_role_name    = module.karpenter[0].node_iam_role_name
    instance_profile_name = module.karpenter[0].instance_profile_name
    queue_name            = module.karpenter[0].queue_name
  } : null
}

output "cluster_ready" {
  description = <<-EOT
    Gate for Kubernetes/Helm resources. Resolves only after the cluster exists
    and its EKS access entries have had time to propagate to the authorizer.
    Depend on this instead of cluster_name to avoid "forbidden" errors on the
    first apply.
  EOT
  value       = time_sleep.access_propagation.id
}
