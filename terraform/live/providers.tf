provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Authenticate to the cluster with the aws CLI exec plugin instead of a static
# data.aws_eks_cluster_auth token. That token is minted once when the data
# source is read and expires after ~15 minutes; a cold apply spends longer than
# that building the VPC, cluster and node group before the first Kubernetes
# call, so the stale token fails with "Unauthorized". The exec plugin runs
# `aws eks get-token` fresh for every API call, so it never expires mid-apply.
provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", var.region]
    }
  }
}
