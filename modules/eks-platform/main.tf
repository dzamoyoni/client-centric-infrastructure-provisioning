# EKS Platform Wrapper Module
# Enterprise-grade EKS cluster with native node group management
# Bypasses terraform-aws-modules/eks managed node groups to avoid count issues
#
# This module creates:
# - EKS cluster (control plane only) via terraform-aws-modules/eks
# - Node groups via native aws_eks_node_group resources
# - EBS CSI driver with IRSA
# - All required IAM roles and policies

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28.0, < 7.0"
    }
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  cluster_name = var.cluster_name
  partition    = data.aws_partition.current.partition
  account_id   = data.aws_caller_identity.current.account_id

  # Standard tags applied to all resources
  standard_tags = {
    Environment     = var.environment
    ManagedBy       = "Terraform"
    CriticalInfra   = "true"
    BackupRequired  = "true"
    SecurityLevel   = "High"
    Region          = var.region
    Layer           = "Platform"
    DeploymentPhase = "Phase-2"
    Architecture    = "Client-Centric"
  }

  # Standard node group labels
  standard_labels = {
    Environment  = var.environment
    ManagedBy    = "Terraform"
    Architecture = "Client-Centric"
  }
}

# =============================================================================
# EKS CLUSTER (Control Plane Only - No Managed Node Groups)
# =============================================================================
# We use the EKS module for cluster creation only, bypassing its managed node
# groups submodule which has count issues when used with for_each.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name    = local.cluster_name
  kubernetes_version = var.cluster_version

  # VPC Configuration
  vpc_id     = var.vpc_id
  subnet_ids = var.platform_subnet_ids

  # Security
  endpoint_public_access       = var.enable_public_access
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.management_cidr_blocks

  # IRSA
  enable_irsa = true

  # Cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true

  # Logging
  enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Core addons only (before node groups exist)
  addons = {
    coredns = {
      most_recent = true
      resolve_conflicts = "OVERWRITE"
      # configuration_values = jsonencode({
      #   tolerations = [
      #     {
      #       key      = "node.kubernetes.io/not-ready"
      #       operator = "Exists"
      #       effect   = "NoSchedule"
      #     }
      #   ]
      # })
    }
    eks-pod-identity-agent = {
      most_recent = true
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      most_recent = true
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      most_recent = true
      resolve_conflicts = "OVERWRITE"
    }
    
  }

  # NO managed node groups here - we create them separately below
  eks_managed_node_groups = {}

  # Access entries
  access_entries = var.access_entries

  # Tags
  tags = merge(local.standard_tags, var.additional_tags)
}

# =============================================================================
# NODE GROUP IAM ROLE
# =============================================================================
# Single IAM role for all node groups in this cluster

resource "aws_iam_role" "node_group" {
  name = "${local.cluster_name}-node-group"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(local.standard_tags, {
    Name = "${local.cluster_name}-node-group-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group.name
}

# =============================================================================
# EKS MANAGED NODE GROUPS (Native Resources)
# =============================================================================
# Using native aws_eks_node_group bypasses the upstream module's count issues

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-${each.value.name_suffix}"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.platform_subnet_ids

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  labels = merge(
    local.standard_labels,
    each.value.labels,
    {
      NodeGroup = each.key
      Client    = each.value.client
    }
  )

  tags = merge(
    local.standard_tags,
    each.value.tags,
    {
      Name      = "${local.cluster_name}-${each.value.name_suffix}"
      Purpose   = coalesce(each.value.purpose, "Client-Centric Node Group")
      Client    = each.value.client
      NodeGroup = each.key
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_group_AmazonSSMManagedInstanceCore,
    module.eks,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# =============================================================================
# EBS CSI DRIVER
# =============================================================================

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "${local.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = merge(local.standard_tags, {
    Name = "${local.cluster_name}-ebs-csi-irsa"
  })
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.standard_tags, {
    Name = "${local.cluster_name}-ebs-csi-addon"
  })

  depends_on = [aws_eks_node_group.this]
}
