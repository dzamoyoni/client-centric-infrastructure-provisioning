# EBS CSI Driver Module with Automated IAM Configuration
# This module ensures EBS CSI driver has proper IAM permissions and IRSA setup

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10"
    }
  }
}

# Data sources for cluster information
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# EBS CSI Driver IRSA (IAM Role for Service Accounts)
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 5.0"

  create_role = true
  role_name   = "${var.cluster_name}-ebs-csi-driver-role"

  provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")

  role_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]

  oidc_fully_qualified_subjects = [
    "system:serviceaccount:kube-system:ebs-csi-controller-sa"
  ]

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-ebs-csi-driver-role"
    Component = "ebs-csi-driver"
  })
}

# EBS CSI Driver Add-on (managed by AWS)
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn

  depends_on = [module.ebs_csi_irsa]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ebs-csi-driver"
  })
}

# Update existing node group IAM roles (fallback for legacy clusters)
resource "aws_iam_role_policy_attachment" "node_group_ebs_csi_policy" {
  count = length(var.node_group_role_names)

  role       = var.node_group_role_names[count.index]
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Create default GP2 StorageClass if it doesn't exist
resource "kubernetes_storage_class_v1" "gp2" {
  count = var.create_gp2_storageclass ? 1 : 0

  metadata {
    name = "gp2"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = var.make_gp2_default ? "true" : "false"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type   = "gp2"
    fsType = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# Create GP3 StorageClass (optional, more performant)
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_gp3_storageclass ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = var.make_gp3_default ? "true" : "false"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type       = "gp3"
    fsType     = "ext4"
    iops       = "3000"
    throughput = "125"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# Note: EBS CSI driver validation can be done manually with:
# kubectl get daemonset ebs-csi-node -n kube-system
# kubectl get deployment ebs-csi-controller -n kube-system
