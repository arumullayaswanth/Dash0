terraform {
  required_version = ">= 1.10.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    # Used to generate Linkerd's trust anchor and identity issuer.
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
