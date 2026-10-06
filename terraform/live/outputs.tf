output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "region" {
  description = "AWS region the cluster runs in."
  value       = var.region
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_cluster.cluster_name}"
}

output "dash0_collector_endpoint" {
  description = "In-cluster OTLP/gRPC endpoint. Point any extra workload at this to get it into Dash0."
  value       = module.platform_addons.dash0_collector_endpoint
}

output "dash0_namespace" {
  description = "Namespace the Dash0 operator runs in."
  value       = module.dash0.namespace
}

output "enabled_addons" {
  description = "Everything this apply installed. Check this to confirm a profile did what you expected."
  value       = module.platform_addons.enabled_addons
}

output "active_mesh" {
  description = "Installed service mesh: istio, linkerd, or none."
  value       = module.platform_addons.active_mesh
}

output "load_balancer_services" {
  description = "Services holding an AWS load balancer. Each bills hourly; check before leaving the cluster up."
  value       = module.platform_addons.load_balancer_services
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "nat_public_ips" {
  description = "Cluster egress IPs, for allowlisting on the Dash0 side if needed."
  value       = module.network.nat_public_ips
}

output "verify_commands" {
  description = "Quick checks that telemetry is flowing, in the order worth running them."
  value = [
    "kubectl get pods -n ${module.dash0.namespace}",
    "kubectl get dash0monitoring --all-namespaces",
    "kubectl logs -n ${module.dash0.namespace} -l app.kubernetes.io/name=opentelemetry-collector --tail=50",
    "kubectl get pods -n otel-demo",
  ]
}

output "demo_app_access" {
  description = "Open the OpenTelemetry demo storefront locally, then browse to http://localhost:8080 to generate traffic and http://localhost:8080/feature to inject failures. Run the commands in order."
  value = [
    "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_cluster.cluster_name}",
    "kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080",
  ]
}

output "demo_frontend_url" {
  description = "Public URL of the OpenTelemetry demo storefront when expose_demo_frontend is on. Browse here directly; append /feature to inject failures. Null when the frontend is not exposed."
  value       = module.platform_addons.demo_frontend_url
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID, or null when disabled. Connect via Console -> EC2 -> Connect -> Session Manager."
  value       = var.enable_bastion ? module.bastion[0].instance_id : null
}

output "bastion_connect_hint" {
  description = "How to open a shell on the bastion to run kubectl against the cluster."
  value       = var.enable_bastion ? module.bastion[0].connect_hint : "bastion disabled (set enable_bastion = true)"
}
