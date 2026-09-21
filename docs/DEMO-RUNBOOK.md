# Demo runbook

Use only **GitHub → Actions → Dash0 EKS lifecycle** for lifecycle operations. Complete [deploy.md](../deploy.md) first. Every apply waits for EKS and verifies metrics, logs, Kubernetes events, and spans in Dash0 before reporting success.

## Deploy

Run the workflow with:

- `action` = `apply`
- `confirm` = `yes`
- `delete_backend` = `false`

This creates the VPC, EKS cluster, node group, bastion, cert-manager, metrics-server, the Dash0 operator and collector, and the OpenTelemetry Demo as a traffic source. Roughly 20–30 minutes.

## What to show

1. Open the workflow **Summary**: action, planned/created counts, readiness, and Dash0 evidence.
2. In Dash0, select the `demo` dataset and filter `k8s.cluster.name = dash0-lab-demo`.
3. Open the **Dash0 EKS Demo Overview** dashboard: ready nodes, running pods, service latency.
4. Open **Kubernetes** and walk cluster → nodes → namespaces → workloads → pods.
5. Open **Services** / **Service Map**. The ~15 demo services were never modified for Dash0; the operator injected instrumentation and the map built itself.
6. Open one distributed **trace** and follow a request across services.
7. From the trace, jump to correlated **Logs** and **Events**.
8. Show **host metrics** per node.

## Trigger a failure on demand

The OpenTelemetry Demo ships feature flags for deliberate breakage. From the bastion:

```
kubectl port-forward -n otel-demo svc/flagd-ui 4000:4000
```

Enable `paymentFailure` or `cartFailure`, then watch the error surface in Dash0 without having told it what to watch. Disable the flag to show recovery.

## Inspect from the cluster

1. Note `bastion_instance_id` in the run Summary.
2. AWS Console → **Systems Manager** → **Session Manager** → **Start session**.
3. Run:
   - `kubectl get nodes -o wide`
   - `kubectl get pods -A`
   - `kubectl get pods -n otel-demo`
   - `kubectl get dash0monitoring -A`

Worth putting on screen: `kubectl get pod -n otel-demo <pod> -o yaml` and pointing at the init container and `OTEL_*` env vars the operator added. That is the value proposition in one screen.

## Enable more technologies

Istio, Cilium, GitOps tools, data stores, and the Prometheus stack are all implemented in `modules/platform-addons` behind feature flags. Edit `terraform/live/env/core.tfvars` to turn them on, then run `apply` again.

Mind the conflict rules in `modules/platform-addons/guards.tf`: Istio and Linkerd cannot coexist, Cilium is a cluster-creation decision, and Envoy Gateway conflicts with kgateway. Plan first and read the counts before approving.

## Teardown

Run the workflow with `action` = `destroy`, `confirm` = `yes`, `delete_backend` = `false`.

It removes the managed Dash0 dashboard, drains Kubernetes LoadBalancer services and PVC-backed workloads, applies a saved destroy plan, retries partial destruction, removes only exact-owned AWS orphans, and fails unless Terraform state and all remaining AWS resource categories are zero. Capture the final Summary as teardown evidence.
