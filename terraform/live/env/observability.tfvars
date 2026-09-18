###############################################################################
# observability: Prometheus CRDs + Grafana + Perses + KEDA
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/observability.tfvars
#
# This is the most useful segment to record, because it is the migration story
# rather than a feature tour.
#
# What this demonstrates in Dash0:
#   - Your existing Prometheus config keeps working. kube-prometheus-stack
#     installs the ServiceMonitor/PodMonitor CRDs plus node-exporter and
#     kube-state-metrics. The Dash0 collector runs the OpenTelemetry target
#     allocator and scrapes those same ServiceMonitors directly.
#     Set keep_prometheus_server = false to remove the Prometheus server entirely
#     and show the metrics still arriving. That is the demo.
#   - Real PromQL against that data in Dash0, so existing queries and dashboards
#     port over rather than being rewritten.
#   - Perses dashboards-as-code: the Dash0 operator watches PersesDashboard
#     resources and syncs them into Dash0. Commit a dashboard, watch it appear.
#   - Prometheus rules synced as Dash0 check rules, same mechanism.
#   - KEDA scaling on queue depth, with both the trigger metric and the resulting
#     replica count visible in one place.
#
# Grafana is left on so you can put the two UIs side by side honestly.
###############################################################################

system_node_instance_types = ["m6i.xlarge"]
system_node_min            = 2
system_node_desired        = 3
system_node_max            = 6

profile_observability = {
  prometheus_stack = true
  grafana          = true
  perses           = true
  keda             = true
  kyverno          = false
  dapr             = false
  keycloak         = false
}

# Start with the server running so you can show the "before". Flip to false and
# re-apply to show the Dash0 collector picking up the same ServiceMonitors with
# no Prometheus server in the path.
keep_prometheus_server = true

# Prometheus needs a PV.
storage_class          = "dash0-gp3"
data_store_volume_size = "8Gi"
