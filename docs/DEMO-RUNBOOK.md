# Demo runbook

Use only **GitHub → Actions → Dash0 EKS lifecycle** for lifecycle operations. Complete [deploy.md](../deploy.md) first. Every apply waits for EKS and verifies metrics, logs, Kubernetes events, and spans in Dash0 before reporting success.

## Core profile

Run with:

- `action=apply`
- `profile=core`
- `confirm=apply:core`
- `delete_backend=false`

This creates EKS, the Dash0 operator, and the OpenTelemetry Demo. The strongest opening is the automatically populated multi-service map: show service dependencies, open one distributed trace, then jump to its correlated logs and Kubernetes resources.

In Dash0, select the configured dataset and filter `k8s.cluster.name = dash0-lab-demo`. Open the managed **Dash0 EKS Demo Overview** dashboard for ready nodes, running pods, and service latency.

## Istio mesh profile

Run `action=apply`, `profile=mesh-istio`, `confirm=apply:mesh-istio`.

Show application spans and Istio proxy spans for the same request. Explain that both reach the in-cluster Dash0 OpenTelemetry collector without exposing a public collector.

Do not combine Istio and Linkerd. The Terraform profile guards reject conflicting meshes.

## Cilium network profile

Use a fresh cluster: `action=apply`, `profile=network-cilium`, `confirm=apply:network-cilium`.

Show Hubble/eBPF network and DNS visibility together with Kubernetes and application telemetry. Cilium is a cluster-creation CNI choice, so destroy this profile before returning to the AWS VPC CNI.

## GitOps profile

Run `action=apply`, `profile=gitops`, `confirm=apply:gitops`.

Show Argo CD and Flux controller health, reconciliation, and synchronization signals. Correlate a deployment/sync event with application latency or errors in the same time range.
## Data profile

Run `action=apply`, `profile=data`, `confirm=apply:data`.

Show PostgreSQL, MySQL, RabbitMQ, and Kafka infrastructure metrics beside client spans. Focus on database latency and message producer/consumer correlation rather than opening every product UI.

## Observability profile

Run `action=apply`, `profile=observability`, `confirm=apply:observability`.

This is the best migration segment. Show that Prometheus ServiceMonitor/PodMonitor resources and exporters remain useful while the Dash0 collector/target allocator scrapes their metrics. Compare Grafana, Perses, and Dash0 honestly. The workflow also applies the version-controlled **Dash0 EKS Demo Overview** dashboard through the Dash0 CLI.

## Everything profile

Run `action=apply`, `profile=everything`, `confirm=apply:everything` only for coexistence testing. It is expensive and too noisy for a focused recording. The profile deliberately excludes combinations that conflict.

## Recording sequence

1. Show the successful GitHub Summary: profile, additions/changes, state count, workload readiness, and Dash0 evidence.
2. Open **Dash0 EKS Demo Overview** with the dataset and cluster filter active.
3. Open Kubernetes resources and compare nodes, namespaces, workloads, pods, CPU, memory, network, and restarts.
4. Open Services/Service Map and follow a request across services.
5. Open a slow or failed trace and correlate it with logs and Kubernetes events.
6. Open the selected profile integration and show one healthy signal and one failure symptom.
7. Restore the failure and show recovery.

## Automatic teardown

After recording, dispatch the same workflow with:

- `action=destroy`
- the exact applied `profile`
- `confirm=destroy:PROFILE`
- `delete_backend=false` for another session, or `true` for final cleanup

The workflow removes the managed Dash0 dashboard, drains Kubernetes LoadBalancer services and PVC-backed workloads, applies a saved destroy plan, retries partial Terraform destruction, removes only exact-owned AWS orphans, and fails unless Terraform state and all remaining AWS resource categories are zero.

Capture the final GitHub Summary as teardown evidence. Full click-by-click instructions and dashboard navigation are in [deploy.md](../deploy.md).
