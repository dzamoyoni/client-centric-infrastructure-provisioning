# Platform Layer 
# PER-CLIENT EKS CLUSTERS - Complete Isolation
# Each client gets a dedicated EKS cluster in their own VPC
# Client config centralized in ROOT /clients.auto.tfvars
# Deploy with: terraform apply -var-file="../../../../../../clients.auto.tfvars"

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
# Layer Metadata - From Shared Config Module
# ============================================================================

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "02-platform"
}

# ============================================================================
# Tagging Configuration
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core parameters
  environment = var.environment
  region      = var.region
  
  # Layer-specific from shared-config module
  layer_name         = module.layer_config.layer_name
  layer_purpose      = module.layer_config.layer_purpose
  deployment_phase   = module.layer_config.deployment_phase
  security_level     = module.layer_config.security_level
  sla_tier           = module.layer_config.sla_tier
  monitoring_level   = module.layer_config.monitoring_level
  maintenance_window = module.layer_config.maintenance_window
  dr_tier            = module.layer_config.dr_tier
  rpo                = module.layer_config.rpo
  rto                = module.layer_config.rto
  patch_group        = module.layer_config.patch_group
  resource_type      = module.layer_config.resource_type
  chargeback_code    = module.layer_config.chargeback_code
  runbook_url        = module.layer_config.runbook_url
  incident_contact   = module.layer_config.incident_contact
  
  # Platform-specific
  kubernetes_version = var.cluster_version
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
# Client config comes from CENTRALIZED ROOT /clients.auto.tfvars
locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs        = data.terraform_remote_state.foundation.outputs.client_vpcs
  availability_zones = data.terraform_remote_state.foundation.outputs.availability_zones
  
  # Filter enabled clients with EKS enabled (from centralized config)
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled && config.eks.enabled
  }
  
  # Filter enabled clients with ALB enabled
  enabled_alb_clients = {
    for name, config in var.clients : name => config
    if config.enabled && try(config.alb.enabled, false)
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
      error_message = "No enabled clients with EKS. Check ROOT /clients.auto.tfvars."
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
# CLIENT CONFIG: Centralized in ROOT /clients.auto.tfvars

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

# ============================================================================
# PER-CLIENT APPLICATION LOAD BALANCERS
# ============================================================================
# Each client gets dedicated ALB(s) based on their tier:
# - Premium: "both" (internet-facing + internal)
# - Standard: "internal" (VPN access only)
# CLIENT CONFIG: Centralized in ROOT /clients.auto.tfvars

module "client_alb" {
  for_each = local.enabled_alb_clients
  
  source = "../../../../../../../modules/alb-per-client"
  
  # Client identification
  client_id   = each.key
  environment = var.environment
  
  # Network configuration from client's dedicated VPC
  vpc_id                     = local.client_vpcs[each.key].vpc_id
  public_subnet_ids          = local.client_vpcs[each.key].public_subnet_ids
  private_subnet_ids         = local.client_vpcs[each.key].eks_subnet_ids
  eks_node_security_group_id = module.client_eks_clusters[each.key].node_security_group_id
  
  # ALB type: internet-facing, internal, or both
  alb_type = each.value.alb.type
  
  # Port configuration
  https_external_port = each.value.alb.https_external_port
  http_external_port  = each.value.alb.http_external_port
  https_nodeport      = each.value.alb.https_nodeport
  http_nodeport       = each.value.alb.http_nodeport
  
  # SSL/TLS configuration
  ssl_certificate_arn          = each.value.alb.ssl_certificate_arn
  ssl_certificate_arn_internal = each.value.alb.ssl_certificate_arn_internal
  ssl_policy                   = each.value.alb.ssl_policy
  redirect_http_to_https       = each.value.alb.redirect_http_to_https
  
  # Security configuration
  allowed_cidr_blocks_public   = each.value.alb.allowed_cidr_blocks_public
  allowed_cidr_blocks_internal = each.value.alb.allowed_cidr_blocks_internal
  
  # Health check configuration
  health_check_path = each.value.alb.health_check_path
  
  # Access logs
  enable_access_logs = each.value.alb.enable_access_logs
  access_logs_bucket = each.value.alb.enable_access_logs ? "${each.key}-alb-logs-${var.region}" : ""
  
  # WAF configuration (only for public ALBs)
  waf_acl_arn = each.value.alb.enable_waf && contains(["internet-facing", "both"], each.value.alb.type) ? try(aws_wafv2_web_acl.client_waf[each.key].arn, null) : null
  
  # Feature flags
  enable_deletion_protection = each.value.alb.enable_deletion_protection
  enable_sticky_sessions     = each.value.alb.enable_sticky_sessions
  
  # Tags from shared-config module
  tags = merge(
    module.tags.common_tags,
    {
      ClientName = each.key
      ClientCode = each.value.client_code
      Tier       = each.value.tier
      Layer      = "02-platform"
      Resource   = "ALB"
    }
  )
  
  depends_on = [module.client_eks_clusters]
}

# ============================================================================
# ALB Target Group Attachments to EKS Auto Scaling Groups
# ============================================================================
# Automatically attach EKS node groups to ALB target groups

resource "aws_autoscaling_attachment" "alb_target_groups" {
  for_each = {
    for pair in flatten([
      for client_name, alb in module.client_alb : [
        for tg_arn in alb.target_group_arns : {
          key             = "${client_name}-${md5(tg_arn)}"
          client_name     = client_name
          tg_arn          = tg_arn
        }
      ]
    ]) : pair.key => pair
  }
  
  autoscaling_group_name = module.client_eks_clusters[each.value.client_name].node_group_asg_names["primary"]
  lb_target_group_arn    = each.value.tg_arn
}

# ============================================================================
# WAF Web ACLs for Internet-Facing ALBs (Optional)
# ============================================================================
# Only created if enable_waf = true and ALB is internet-facing

resource "aws_wafv2_web_acl" "client_waf" {
  for_each = {
    for name, config in local.enabled_alb_clients : name => config
    if try(config.alb.enable_waf, false) && contains(["internet-facing", "both"], config.alb.type)
  }
  
  name  = "${each.key}-${var.environment}-waf"
  scope = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  # AWS Managed Rule: Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${each.key}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }
  
  # AWS Managed Rule: Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${each.key}-KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }
  
  # AWS Managed Rule: SQL Injection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${each.key}-SQLi"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${each.key}-WAF"
    sampled_requests_enabled   = true
  }
  
  tags = merge(
    module.tags.common_tags,
    {
      Name       = "${each.key}-${var.environment}-waf"
      ClientName = each.key
      Resource   = "WAF"
    }
  )
}
