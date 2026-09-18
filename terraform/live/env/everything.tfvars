###############################################################################
# everything: the maximum set that can safely coexist
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/everything.tfvars
#
# READ THIS FIRST. This is expensive and slow. Roughly $1.50-2.50/hour depending
# on how many load balancers end up provisioned, and 25-35 minutes to converge.
# It exists to prove the whole catalog works together, not as a demo profile.
# For recording, use the focused profiles instead.
#
# What is deliberately excluded, and why:
#   - Linkerd: conflicts with Istio. Both inject sidecars.
#   - Cilium: cni_mode is a cluster-creation decision, not a layer. Use
#     network-cilium.tfvars on a fresh cluster.
#   - kgateway: conflicts with Envoy Gateway over Gateway API CRD ownership.
#   - Emissary: conflicts with Istio mTLS STRICT health checks.
#   - Contour and HAProxy: no conflict, just three more load balancers for no
#     additional narrative. Enable individually if you want to compare them.
#
# The module's guards enforce the first four of those, so removing this comment
# and enabling them anyway will fail at plan time with an explanation.
###############################################################################

# Karpenter is not optional at this size. The workload does not fit a fixed node
# group without a lot of guessing, and spot pricing takes the edge off the bill.
enable_karpenter = true

system_node_instance_types = ["m6i.xlarge"]
system_node_min            = 2
system_node_desired        = 3
system_node_max            = 10

profile_platform = {
  cert_manager   = true
  metrics_server = true
}

profile_mesh = {
  istio   = true
  linkerd = false # conflicts with Istio
}

profile_ingress = {
  traefik       = true
  ingress_nginx = true
  contour       = false
  emissary      = false # conflicts with Istio mTLS
  haproxy       = false
}

profile_gateways = {
  envoy_gateway = true
  kgateway      = false # conflicts with Envoy Gateway CRDs
  agentgateway  = true
}

profile_gitops = {
  argocd   = true
  fluxcd   = true
  atlantis = true
}

profile_data_stores = {
  postgres   = true
  mysql      = true
  rabbitmq   = true
  kafka      = true
  clickhouse = true
  tigerdata  = true
}

profile_observability = {
  prometheus_stack = true
  grafana          = true
  perses           = true
  keda             = true
  kyverno          = true
  dapr             = true
  keycloak         = true
}

keep_prometheus_server = true

# With this many workloads, instrumenting everything at once causes a large
# simultaneous restart. Leave it lazy.
instrument_workloads_mode = "created-and-updated"

storage_class          = "dash0-gp3"
data_store_volume_size = "8Gi"
