###############################################################################
# gitops: ArgoCD + FluxCD + Atlantis
#
#   terraform apply -var-file=env/core.tfvars -var-file=env/gitops.tfvars
#
# What this demonstrates in Dash0:
#   - Dash0 ships pre-built check rules for ArgoCD sync and health state via the
#     Integrations Hub, so this is the natural place to show that catalog rather
#     than hand-building alerts.
#   - Deployment events correlated with telemetry: trigger a sync, watch the
#     rollout and the resulting latency change in the same Dash0 view.
#   - Flux controllers and Atlantis publish Prometheus metrics that the Dash0
#     collector scrapes from pod annotations, no Prometheus server involved.
#
# All three coexist without conflict. ArgoCD and Flux will both happily watch the
# same repo, which is itself worth showing.
###############################################################################

system_node_instance_types = ["m6i.large"]
system_node_min            = 2
system_node_desired        = 3
system_node_max            = 5

profile_gitops = {
  argocd   = true
  fluxcd   = true
  atlantis = true
}

# Narrow this to your own org before letting Atlantis near a real repo.
atlantis_repo_allowlist = "github.com/*/*"

# ArgoCD server is ClusterIP with --insecure, so reach it by port-forward:
#   kubectl port-forward -n argocd svc/argocd-server 8080:80
# Initial admin password:
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath='{.data.password}' | base64 -d
