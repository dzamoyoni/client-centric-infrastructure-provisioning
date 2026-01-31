# Platform Layer - Production
# PER-CLIENT EKS CLUSTERS - Complete Isolation
# Each client gets a dedicated EKS cluster in their own VPC

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  backend "s3" {
    # Backend configuration loaded from file
  }
}

# ============================================================================
# Centralized Tagging Configuration
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core configuration
  environment      = var.environment
  layer_name       = "platform"
  region           = var.region
  
  # Layer-specific configuration
  layer_purpose    = "EKS Cluster Management"
  deployment_phase = "Phase-2"
  
  # Infrastructure classification
  critical_infrastructure = "true"
  backup_required        = "true"
  security_level         = "Critical"  # EKS is critical
  
  # Cost management (FinOps aligned)
  cost_center      = "IT-Infrastructure"
  billing_group    = "Platform-Engineering"
  chargeback_code  = "EST1-PLATFORM-001"
  resource_type    = "EKS"
  
  # Operational settings (Enhanced for industrial standards)
  sla_tier           = "Platinum"  # EKS needs highest SLA
  monitoring_level   = "Premium"
  maintenance_window = "Sunday-02:00-04:00-UTC"
  dr_tier            = "Tier-1"  # Mission Critical
  rpo                = "1h"
  rto                = "1h"
  patch_group        = "Critical"
  runbook_url        = "https://wiki.company.com/runbooks/eks-platform"
  incident_contact   = "platform-oncall@company.com"
  
  # Data management
  data_classification  = "Internal"
  data_residency       = "US"
  encryption_required  = "true"
  
  # Governance
  compliance_framework = "SOC2-ISO27001"
  
  # Platform-specific
  kubernetes_version = var.cluster_version
  terraform_module   = "modules/eks-platform"
}

provider "aws" {
  region = var.region

  # Use minimal_tags to stay under AWS 50-tag limit
  default_tags {
    tags = module.tags.minimal_tags
  }
}

# DATA SOURCES - Foundation Layer Outputs
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/01-foundation/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

#  LOCALS - Per-Client Configuration
locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs        = data.terraform_remote_state.foundation.outputs.client_vpcs
  availability_zones = data.terraform_remote_state.foundation.outputs.availability_zones
  
  # Filter enabled clients with EKS enabled
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled && config.eks.enabled
  }
  
  # Validate all enabled clients have VPCs from foundation layer
  missing_vpcs = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_vpcs), name)
  ]
  
  # Per-client EKS cluster configuration
  client_clusters = {
    for name, config in local.enabled_clients : name => {
      cluster_name    = "${name}-${var.environment}-${var.region}"
      vpc_id          = local.client_vpcs[name].vpc_id
      eks_subnet_ids  = local.client_vpcs[name].eks_subnet_ids
      eks_sg_id       = local.client_vpcs[name].eks_security_group_id
      vpc_cidr        = local.client_vpcs[name].vpc_cidr
      client_code     = config.client_code
      tier            = config.tier
      
      # Node group configuration
      node_group = {
        instance_types = config.eks.instance_types
        min_size       = config.eks.min_size
        max_size       = config.eks.max_size
        desired_size   = config.eks.desired_size
        disk_size      = config.eks.disk_size
        capacity_type  = config.eks.capacity_type
      }
      
      # Metadata
      metadata = config.metadata
    }
  }
}

# VALIDATION CHECKS
resource "null_resource" "cross_layer_validation" {
  lifecycle {
    precondition {
      condition     = length(local.missing_vpcs) == 0
      error_message = "Missing VPCs from foundation layer for clients: ${join(", ", local.missing_vpcs)}. Ensure foundation layer is applied."
    }
    
    precondition {
      condition     = length(local.enabled_clients) > 0
      error_message = "No enabled clients with EKS. Check clients.auto.tfvars."
    }
  }
  
  triggers = {
    foundation_vpc_ids = md5(jsonencode({
      for name in keys(local.enabled_clients) : name => local.client_vpcs[name].vpc_id
    }))
    platform_config = md5(jsonencode({
      # project_name removed - using client-centric naming
      environment  = var.environment
      region       = var.region
      clients      = local.enabled_clients
    }))
  }
}

# ============================================================================
# PER-CLIENT EKS CLUSTERS - Complete Infrastructure Isolation
# ============================================================================
# Each client gets a dedicated EKS cluster in their own VPC
# No shared resources - complete isolation for security and compliance

module "client_eks_clusters" {
  for_each = local.client_clusters
  
  source = "../../../../../../../modules/eks-platform"

  # Core configuration
  environment  = var.environment
  region       = var.region

  # Client-specific cluster name
  cluster_name    = each.value.cluster_name
  cluster_version = var.cluster_version

  # Network configuration from client's dedicated VPC
  vpc_id              = each.value.vpc_id
  platform_subnet_ids = each.value.eks_subnet_ids

  # Security configuration
  enable_public_access   = var.enable_public_access
  management_cidr_blocks = var.management_cidr_blocks
  log_retention_days     = 30

  # Client node group
  node_groups = {
    primary = {
      name_suffix    = "${each.value.client_code}-ng"
      instance_types = each.value.node_group.instance_types
      min_size       = each.value.node_group.min_size
      max_size       = each.value.node_group.max_size
      desired_size   = each.value.node_group.desired_size
      disk_size      = each.value.node_group.disk_size
      capacity_type  = each.value.node_group.capacity_type
      
      # Client identification
      client  = each.key
      purpose = "${each.value.metadata.full_name} Primary Node Group"
      
      # Labels for workload placement
      labels = {
        NodeGroup    = "primary"
        ClientName   = each.key
        ClientCode   = each.value.client_code
        Tier         = each.value.tier
        Environment  = var.environment
      }
      
      # Tags
      tags = {
        NodeGroupPurpose = "client-workloads"
        ClientName       = each.key
        ClientCode       = each.value.client_code
        Tier             = each.value.tier
      }
    }
  }

  # Access configuration
  access_entries = {
    admin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Client-specific tags
  additional_tags = {
    ClientName = each.key
    ClientCode = each.value.client_code
    Tier       = each.value.tier
    Industry   = each.value.metadata.industry
  }
  
  depends_on = [null_resource.cross_layer_validation]
}

# ============================================================================
# Per-Client Security Group Rules
# ============================================================================
# Additional security group rules for each client's EKS cluster

resource "aws_security_group_rule" "client_node_to_node_kubelet" {
  for_each = module.client_eks_clusters
  
  description              = "Allow node-to-node kubelet communication for ${each.key}"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = each.value.node_security_group_id
  source_security_group_id = each.value.node_security_group_id
}

#  DATA SOURCE - Current AWS account
data "aws_caller_identity" "current" {}
