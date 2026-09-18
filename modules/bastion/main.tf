###############################################################################
# Bastion / jump host
#
# A small Amazon Linux 2023 EC2 instance you connect to from the AWS Console via
# SSM Session Manager (no SSH key, no public IP, no open inbound ports). It has
# kubectl, helm and the AWS CLI pre-installed and its kubeconfig pointed at the
# demo cluster, so you can inspect the cluster and run commands on camera.
#
# Access path: AWS Console -> EC2 -> select the instance -> Connect ->
# Session Manager -> Connect. Or Systems Manager -> Session Manager.
###############################################################################

data "aws_partition" "current" {}

# Latest Amazon Linux 2023 AMI, resolved from the public SSM parameter so no AMI
# ID is hardcoded per region.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# IAM: SSM managed access plus permission to describe the cluster and assume
# cluster access through an EKS access entry (created by the root stack).
###############################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Session Manager connectivity.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Just enough to run `aws eks update-kubeconfig` and describe the cluster.
data "aws_iam_policy_document" "eks_describe" {
  statement {
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eks_describe" {
  name   = "${var.name}-bastion-eks-describe"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.eks_describe.json
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name
  tags = var.tags
}

###############################################################################
# Security group: no inbound. Egress only, so it can reach the API server,
# ECR/S3 and SSM endpoints. SSM works purely over outbound HTTPS.
###############################################################################

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Bastion egress only; access is via SSM Session Manager."
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-bastion" })
}

locals {
  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    dnf install -y tar gzip

    # kubectl (matching the cluster minor version stream)
    curl -sSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -sSL https://dl.k8s.io/release/stable-${var.kubectl_version}.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl

    # helm
    curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Point kubeconfig at the cluster for the default ssm-user, on every login.
    cat >/etc/profile.d/kubeconfig.sh <<'PROFILE'
    export AWS_REGION=${var.region}
    export KUBECONFIG=$HOME/.kube/config
    if [ ! -f "$KUBECONFIG" ]; then
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} >/dev/null 2>&1 || true
    fi
    PROFILE
  EOT
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # No public IP; reached only through SSM.
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = local.user_data

  tags = merge(var.tags, { Name = "${var.name}-bastion" })
}
