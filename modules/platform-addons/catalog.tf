###############################################################################
# Technology catalog
#
# Every chart this repo can install, with a pinned version verified against the
# upstream repo. Keeping them in one map means a single place to bump versions
# and a single place to see what a profile turns on.
#
# Versions confirmed against the live chart repositories.
###############################################################################

locals {
  catalog = {
    # ---------------------------------------------------------------- platform
    cert_manager = {
      release    = "cert-manager"
      repository = "https://charts.jetstack.io"
      chart      = "cert-manager"
      version    = "v1.21.2"
      namespace  = "cert-manager"
    }
    metrics_server = {
      release    = "metrics-server"
      repository = "https://kubernetes-sigs.github.io/metrics-server/"
      chart      = "metrics-server"
      version    = "3.14.0"
      namespace  = "kube-system"
    }
    karpenter = {
      release    = "karpenter"
      repository = "oci://public.ecr.aws/karpenter"
      chart      = "karpenter"
      version    = "1.14.1"
      namespace  = "kube-system"
    }

    # ------------------------------------------------------------------- mesh
    cilium = {
      release    = "cilium"
      repository = "https://helm.cilium.io"
      chart      = "cilium"
      version    = "1.20.2"
      namespace  = "kube-system"
    }
    istio_base = {
      release    = "istio-base"
      repository = "https://istio-release.storage.googleapis.com/charts"
      chart      = "base"
      version    = "1.30.4"
      namespace  = "istio-system"
    }
    istiod = {
      release    = "istiod"
      repository = "https://istio-release.storage.googleapis.com/charts"
      chart      = "istiod"
      version    = "1.30.4"
      namespace  = "istio-system"
    }
    istio_gateway = {
      release    = "istio-ingressgateway"
      repository = "https://istio-release.storage.googleapis.com/charts"
      chart      = "gateway"
      version    = "1.30.4"
      namespace  = "istio-ingress"
    }
    linkerd_crds = {
      release    = "linkerd-crds"
      repository = "https://helm.linkerd.io/edge"
      chart      = "linkerd-crds"
      version    = "2026.9.2"
      namespace  = "linkerd"
    }
    linkerd_control_plane = {
      release    = "linkerd-control-plane"
      repository = "https://helm.linkerd.io/edge"
      chart      = "linkerd-control-plane"
      version    = "2026.9.2"
      namespace  = "linkerd"
    }

    # ---------------------------------------------------------------- ingress
    traefik = {
      release    = "traefik"
      repository = "https://traefik.github.io/charts"
      chart      = "traefik"
      version    = "41.5.0"
      namespace  = "traefik"
    }
    ingress_nginx = {
      release    = "ingress-nginx"
      repository = "https://kubernetes.github.io/ingress-nginx"
      chart      = "ingress-nginx"
      version    = "4.15.1"
      namespace  = "ingress-nginx"
    }
    contour = {
      release    = "contour"
      repository = "https://projectcontour.github.io/helm-charts"
      chart      = "contour"
      version    = "0.8.0"
      namespace  = "projectcontour"
    }
    emissary = {
      release    = "emissary-ingress"
      repository = "https://app.getambassador.io"
      chart      = "emissary-ingress"
      version    = "8.12.2"
      namespace  = "emissary"
    }
    haproxy = {
      release    = "haproxy-ingress"
      repository = "https://haproxytech.github.io/helm-charts"
      chart      = "kubernetes-ingress"
      version    = "1.54.1"
      namespace  = "haproxy"
    }

    # --------------------------------------------------------------- gateways
    envoy_gateway = {
      release    = "envoy-gateway"
      repository = "oci://docker.io/envoyproxy"
      chart      = "gateway-helm"
      version    = "1.9.1"
      namespace  = "envoy-gateway-system"
    }
    kgateway_crds = {
      release    = "kgateway-crds"
      repository = "oci://cr.kgateway.dev/kgateway-dev/charts"
      chart      = "kgateway-crds"
      version    = "2.4.4"
      namespace  = "kgateway-system"
    }
    kgateway = {
      release    = "kgateway"
      repository = "oci://cr.kgateway.dev/kgateway-dev/charts"
      chart      = "kgateway"
      version    = "2.4.4"
      namespace  = "kgateway-system"
    }
    agentgateway = {
      release    = "agentgateway"
      repository = "oci://ghcr.io/agentgateway/charts"
      chart      = "agentgateway"
      version    = "1.5.0"
      namespace  = "agentgateway"
    }

    # ----------------------------------------------------------------- gitops
    argocd = {
      release    = "argocd"
      repository = "https://argoproj.github.io/argo-helm"
      chart      = "argo-cd"
      version    = "10.9.1"
      namespace  = "argocd"
    }
    fluxcd = {
      release    = "flux2"
      repository = "https://fluxcd-community.github.io/helm-charts"
      chart      = "flux2"
      version    = "2.19.0"
      namespace  = "flux-system"
    }
    atlantis = {
      release    = "atlantis"
      repository = "https://runatlantis.github.io/helm-charts"
      chart      = "atlantis"
      version    = "6.15.1"
      namespace  = "atlantis"
    }

    # ------------------------------------------------------------ data stores
    postgres_operator = {
      release    = "cloudnative-pg"
      repository = "https://cloudnative-pg.github.io/charts"
      chart      = "cloudnative-pg"
      version    = "0.29.0"
      namespace  = "cnpg-system"
    }
    mysql = {
      release    = "mysql"
      repository = "oci://registry-1.docker.io/bitnamicharts"
      chart      = "mysql"
      version    = "14.0.3"
      namespace  = "mysql"
    }
    rabbitmq = {
      release    = "rabbitmq"
      repository = "oci://registry-1.docker.io/bitnamicharts"
      chart      = "rabbitmq"
      version    = "16.0.14"
      namespace  = "rabbitmq"
    }
    strimzi = {
      release    = "strimzi-kafka-operator"
      repository = "https://strimzi.io/charts"
      chart      = "strimzi-kafka-operator"
      version    = "1.2.0"
      namespace  = "kafka"
    }
    clickhouse_operator = {
      release    = "clickhouse-operator"
      repository = "https://helm.altinity.com"
      chart      = "altinity-clickhouse-operator"
      version    = "0.27.3"
      namespace  = "clickhouse"
    }
    tigerdata = {
      release    = "timescaledb"
      repository = "https://charts.timescale.com"
      chart      = "timescaledb-single"
      version    = "0.33.1"
      namespace  = "tigerdata"
    }

    # -------------------------------------------------- observability & policy
    kube_prometheus_stack = {
      release    = "kube-prometheus-stack"
      repository = "https://prometheus-community.github.io/helm-charts"
      chart      = "kube-prometheus-stack"
      version    = "91.4.1"
      namespace  = "monitoring"
    }
    perses = {
      release    = "perses"
      repository = "https://perses.github.io/helm-charts"
      chart      = "perses"
      version    = "0.23.2"
      namespace  = "perses"
    }
    keda = {
      release    = "keda"
      repository = "https://kedacore.github.io/charts"
      chart      = "keda"
      version    = "2.20.2"
      namespace  = "keda"
    }
    kyverno = {
      release    = "kyverno"
      repository = "https://kyverno.github.io/kyverno"
      chart      = "kyverno"
      version    = "3.9.1"
      namespace  = "kyverno"
    }
    dapr = {
      release    = "dapr"
      repository = "https://dapr.github.io/helm-charts"
      chart      = "dapr"
      version    = "1.18.4"
      namespace  = "dapr-system"
    }
    keycloak = {
      release    = "keycloak"
      repository = "https://codecentric.github.io/helm-charts"
      chart      = "keycloakx"
      version    = "7.3.1"
      namespace  = "keycloak"
    }

    # ------------------------------------------------------------- demo app
    otel_demo = {
      release    = "opentelemetry-demo"
      repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
      chart      = "opentelemetry-demo"
      version    = var.otel_demo_chart_version
      namespace  = "otel-demo"
    }
  }
}
