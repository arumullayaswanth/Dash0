###############################################################################
# mesh-istio: Istio + Traefik
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/mesh-istio.tfvars
#
# What this demonstrates in Dash0:
#   - Mesh spans with no application changes. Istio is configured with an
#     OpenTelemetry extension provider pointing at the Dash0 collector, so every
#     sidecar reports spans directly over OTLP.
#   - Envoy access logs to stdout, collected by the Dash0 filelog receiver, so
#     logs and traces for the same request land together.
#   - Traefik in front, also exporting OTLP natively rather than being scraped.
#     Two OTLP-native proxies, one endpoint, no Prometheus in the path.
#
# Sidecars add roughly 100 MiB and a container per pod, so the node group goes up
# a size.
###############################################################################

system_node_instance_types = ["m6i.xlarge"]
system_node_min            = 2
system_node_desired        = 2
system_node_max            = 5

profile_mesh = {
  istio = true
}

# Traefik is the OTLP-native ingress, which pairs well with the mesh story.
# Note: Emissary is deliberately not used with Istio; mTLS STRICT breaks its
# health checks and the guard in the module will reject that combination.
profile_ingress = {
  traefik = true
}

# Instrument existing workloads too, so the demo app picks up sidecars and Dash0
# instrumentation in the same rollout instead of two separate restarts.
instrument_workloads_mode = "all"
