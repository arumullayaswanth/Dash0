output "dash0_collector_endpoint" {
  description = "In-cluster OTLP/gRPC address of the Dash0 operator's collector. Point any extra workload at this."
  value       = local.dash0_collector_grpc
}

output "active_mesh" {
  description = "Which service mesh is installed: istio, linkerd, or none."
  value       = local.active_mesh
}

output "enabled_addons" {
  description = "Flat list of every addon this apply installed. Handy for confirming a profile did what you expected."
  value = compact([
    var.platform.cert_manager ? "cert-manager" : "",
    var.platform.metrics_server ? "metrics-server" : "",
    var.karpenter != null ? "karpenter" : "",
    var.cni_mode == "cilium" ? "cilium" : "",
    var.mesh.istio ? "istio" : "",
    var.mesh.linkerd ? "linkerd" : "",
    var.ingress.traefik ? "traefik" : "",
    var.ingress.ingress_nginx ? "ingress-nginx" : "",
    var.ingress.contour ? "contour" : "",
    var.ingress.emissary ? "emissary" : "",
    var.ingress.haproxy ? "haproxy" : "",
    var.gateways.envoy_gateway ? "envoy-gateway" : "",
    var.gateways.kgateway ? "kgateway" : "",
    var.gateways.agentgateway ? "agentgateway" : "",
    var.gitops.argocd ? "argocd" : "",
    var.gitops.fluxcd ? "fluxcd" : "",
    var.gitops.atlantis ? "atlantis" : "",
    var.data_stores.postgres ? "postgres" : "",
    var.data_stores.mysql ? "mysql" : "",
    var.data_stores.rabbitmq ? "rabbitmq" : "",
    var.data_stores.kafka ? "kafka" : "",
    var.data_stores.clickhouse ? "clickhouse" : "",
    var.data_stores.tigerdata ? "tigerdata" : "",
    var.observability.prometheus_stack ? "kube-prometheus-stack" : "",
    var.observability.grafana ? "grafana" : "",
    var.observability.perses ? "perses" : "",
    var.observability.keda ? "keda" : "",
    var.observability.kyverno ? "kyverno" : "",
    var.observability.dapr ? "dapr" : "",
    var.observability.keycloak ? "keycloak" : "",
    var.demo_app ? "opentelemetry-demo" : "",
  ])
}

output "namespaces" {
  description = "Namespaces created by the enabled addons, for quick kubectl targeting."
  value = {
    for k, v in local.catalog : k => v.namespace
  }
}

output "load_balancer_services" {
  description = <<-EOT
    Services that provision an AWS load balancer. Each one bills hourly, so this
    is the list to check before leaving a cluster running overnight.
  EOT
  value = compact([
    var.ingress.traefik ? "${local.catalog.traefik.namespace}/traefik" : "",
    var.ingress.ingress_nginx ? "${local.catalog.ingress_nginx.namespace}/ingress-nginx-controller" : "",
    var.ingress.contour ? "${local.catalog.contour.namespace}/envoy" : "",
    var.ingress.emissary ? "${local.catalog.emissary.namespace}/emissary-ingress" : "",
    var.ingress.haproxy ? "${local.catalog.haproxy.namespace}/haproxy-ingress" : "",
    var.mesh.istio ? "${local.catalog.istio_gateway.namespace}/istio-ingressgateway" : "",
  ])
}
