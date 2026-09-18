###############################################################################
# network-cilium: Cilium as the CNI, with Hubble
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/network-cilium.tfvars
#
# IMPORTANT: cni_mode is a cluster-creation decision, not a toggle. It removes
# the aws-node DaemonSet so Cilium can own pod IPs. Do not flip this on a running
# cluster; destroy and recreate, or you will strand pods with no networking.
#
# What this demonstrates in Dash0:
#   - Hubble's L7 metrics: HTTP status codes, latency and DNS queries per
#     workload, derived from eBPF with zero application instrumentation. This is
#     the strongest "observability without code changes" segment available.
#   - Dropped-packet and policy-denial metrics, which are genuinely hard to get
#     any other way.
#   - kube-proxy replaced entirely, so the kubeProxy ServiceMonitor is disabled
#     in the observability profile to avoid permanently-down targets.
#
# Cilium runs in ENI mode, so pods still get real VPC IPs. Security groups and
# flow logs keep working the way they did with the AWS CNI.
###############################################################################

cni_mode = "cilium"

# Cilium's agent is a DaemonSet with a meaningful memory footprint, and Hubble
# relay plus UI add two more deployments.
system_node_instance_types = ["m6i.xlarge"]
system_node_min            = 2
system_node_desired        = 2
system_node_max            = 5

# Cilium can also serve Gateway API and replace an ingress controller, but that
# is left off here so CRD ownership stays unambiguous.
profile_ingress = {}
profile_mesh    = {}
