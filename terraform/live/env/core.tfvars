###############################################################################
# core: cluster + Dash0 + the OTel demo, nothing else
#
# This is the baseline every other profile layers on top of. Always pass it
# first:
#   terraform apply -var-file=env/core.tfvars
#   terraform apply -var-file=env/core.tfvars -var-file=env/mesh-istio.tfvars
#
# Fits comfortably on two m6i.large nodes. Cheapest thing that still shows a
# populated Dash0.
###############################################################################

project     = "dash0-lab"
environment = "demo"
region      = "us-east-1"

# Two AZs and one NAT gateway. EKS needs at least two AZs; a third only adds
# cost on a demo cluster.
az_count           = 2
single_nat_gateway = true

kubernetes_version = "1.34"

system_node_instance_types = ["m6i.large"]
system_node_min            = 2
system_node_desired        = 2
system_node_max            = 4

# Karpenter is off here. Turn it on once you enable heavier profiles rather than
# guessing a bigger node count.
enable_karpenter = false

# Only the baseline plumbing.
profile_platform = {
  cert_manager   = true
  metrics_server = true
}

# The demo app is the traffic source. Without it Dash0 shows an idle cluster.
enable_demo_app = true

# Dash0 endpoints and token come from terraform.tfvars or TF_VAR_* env vars.
# See docs/SETUP.md.
