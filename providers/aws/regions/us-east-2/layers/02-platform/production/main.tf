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
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  backend "s3" {}
}

# ==============================================================================
# Layer Metadata - From Shared Config Module
# ==============================================================================

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "02-platform"
}

# ==============================================================================
# Tagging Configuration
# ==============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"

  environment = var.environment
  region      = var.region

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

  kubernetes_version = var.cluster_version
}

provider "aws" {
  region = var.region

  default_tags {
    tags = module.tags.minimal_tags
  }
}

# ==============================================================================
# DATA SOURCES - Foundation Layer Outputs
# ==============================================================================

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    # bucket = var.terraform_state_bucket
    bucket = "terraform-state-${var.region}-${var.environment}-myorg"
    key    = "${var.region}/01-foundation/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

data "aws_caller_identity" "current" {}

# ==============================================================================
# LOCALS - Per-Client Configuration
# ==============================================================================

locals {
  client_vpcs        = data.terraform_remote_state.foundation.outputs.client_vpcs
  availability_zones = data.terraform_remote_state.foundation.outputs.availability_zones

  # Clients with EKS enabled
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled && config.eks.enabled
  }

  # FIX: ALB enablement guard uses try() because alb block is optional(object, null).
  # try(config.alb.enabled, false) safely returns false when alb is null rather
  # than throwing "attempt to get attribute from null value".
  enabled_alb_clients = {
    for name, config in var.clients : name => config
    if config.enabled && try(config.alb.enabled, false)
  }

  # Validate all enabled clients have VPCs provisioned by Layer 01
  missing_vpcs = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_vpcs), name)
  ]

  # Per-client EKS cluster configuration derived from centralized clients map
  client_clusters = {
    for name, config in local.enabled_clients : name => {
      cluster_name   = "${name}-${var.environment}"
      vpc_id         = local.client_vpcs[name].vpc_id
      eks_subnet_ids = local.client_vpcs[name].eks_subnet_ids
      eks_sg_id      = local.client_vpcs[name].eks_security_group_id
      vpc_cidr       = local.client_vpcs[name].vpc_cidr
      client_code    = config.client_code
      tier           = config.tier

      node_group = {
        instance_types = config.eks.instance_types
        min_size       = config.eks.min_size
        max_size       = config.eks.max_size
        desired_size   = config.eks.desired_size
        disk_size      = config.eks.disk_size
        capacity_type  = config.eks.capacity_type
      }

      metadata = config.metadata
    }
  }
}

# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

resource "null_resource" "cross_layer_validation" {
  lifecycle {
    precondition {
      condition     = length(local.missing_vpcs) == 0
      error_message = "Missing VPCs from foundation layer for clients: ${join(", ", local.missing_vpcs)}. Apply Layer 01 first."
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
      environment = var.environment
      region      = var.region
      clients     = local.enabled_clients
    }))
  }
}

# ==============================================================================
# PER-CLIENT EKS CLUSTERS
# ==============================================================================

module "client_eks_clusters" {
  for_each = local.client_clusters

  source = "../../../../../../../modules/eks-platform"

  environment  = var.environment
  region       = var.region

  cluster_name    = each.value.cluster_name
  cluster_version = var.cluster_version

  vpc_id              = each.value.vpc_id
  platform_subnet_ids = each.value.eks_subnet_ids

  enable_public_access   = var.enable_public_access
  management_cidr_blocks = var.management_cidr_blocks
  log_retention_days     = 30

  node_groups = {
    primary = {
      name_suffix    = "ng"
      instance_types = each.value.node_group.instance_types
      min_size       = each.value.node_group.min_size
      max_size       = each.value.node_group.max_size
      desired_size   = each.value.node_group.desired_size
      disk_size      = each.value.node_group.disk_size
      capacity_type  = each.value.node_group.capacity_type

      client  = each.key
      purpose = "${each.value.metadata.full_name} Primary Node Group"

      labels = {
        NodeGroup   = "primary"
        ClientName  = each.key
        ClientCode  = each.value.client_code
        Tier        = each.value.tier
        Environment = var.environment
      }

      tags = {
        NodeGroupPurpose = "client-workloads"
        ClientName       = each.key
        ClientCode       = each.value.client_code
        Tier             = each.value.tier
      }
    }
  }

  access_entries = {
    root = {
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

  additional_tags = {
    ClientName = each.key
    ClientCode = each.value.client_code
    Tier       = each.value.tier
    Industry   = each.value.metadata.industry
  }

  depends_on = [null_resource.cross_layer_validation]
}

# ==============================================================================
# Per-Client Security Group Rules
# ==============================================================================

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

# ==============================================================================
# PER-CLIENT APPLICATION LOAD BALANCERS
# ==============================================================================
# FIX: local.enabled_alb_clients already guards with try(config.alb.enabled, false)
# so every config reference inside this module block is guaranteed non-null.
# However we still use try() on ssl_certificate_arn_internal because the tfvars
# sets it to null (which coerces to "" via the optional default, but being
# explicit here prevents surprises if the default ever changes).

module "client_alb" {
  for_each = local.enabled_alb_clients

  source = "../../../../../../../modules/alb-per-client"

  client_id   = each.key
  environment = var.environment

  vpc_id                     = local.client_vpcs[each.key].vpc_id
  public_subnet_ids          = local.client_vpcs[each.key].public_subnet_ids
  private_subnet_ids         = local.client_vpcs[each.key].eks_subnet_ids
  eks_node_security_group_id = module.client_eks_clusters[each.key].node_security_group_id

  alb_type = each.value.alb.type

  https_external_port = each.value.alb.https_external_port
  http_external_port  = each.value.alb.http_external_port
  https_nodeport      = each.value.alb.https_nodeport
  http_nodeport       = each.value.alb.http_nodeport

  ssl_certificate_arn = each.value.alb.ssl_certificate_arn
  ssl_certificate_arn_internal = (
    each.value.alb.ssl_certificate_arn_internal != ""
    ? each.value.alb.ssl_certificate_arn_internal
    : null
  )
  ssl_policy             = each.value.alb.ssl_policy
  redirect_http_to_https = each.value.alb.redirect_http_to_https

  allowed_cidr_blocks_public   = each.value.alb.allowed_cidr_blocks_public
  allowed_cidr_blocks_internal = each.value.alb.allowed_cidr_blocks_internal

  health_check_path = each.value.alb.health_check_path

  enable_access_logs = each.value.alb.enable_access_logs
  access_logs_bucket = each.value.alb.enable_access_logs ? "${each.key}-alb-logs-${var.region}" : ""


  enable_waf = (
  each.value.alb.enable_waf && contains(["internet-facing", "both"], each.value.alb.type)
  )
  waf_acl_arn = (
  each.value.alb.enable_waf && contains(["internet-facing", "both"], each.value.alb.type)
  ? try(aws_wafv2_web_acl.client_waf[each.key].arn, null)
  : null
  )
  # waf_acl_arn = (
  #   each.value.alb.enable_waf && contains(["internet-facing", "both"], each.value.alb.type)
  #   ? try(aws_wafv2_web_acl.client_waf[each.key].arn, null)
  #   : null
  # )

  enable_deletion_protection = each.value.alb.enable_deletion_protection
  enable_sticky_sessions     = each.value.alb.enable_sticky_sessions

  tags = merge(
    module.tags.minimal_tags,
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

# ==============================================================================
# ALB → EKS Auto Scaling Group Attachments
# ==============================================================================
# FIX: node_group_asg_names["primary"] is now a valid reference because we
# added the node_group_asg_names output to the eks-platform wrapper module.

# resource "aws_autoscaling_attachment" "alb_target_groups" {
#   for_each = {
#     for pair in flatten([
#       for client_name, alb in module.client_alb : [
#         for tg_arn in alb.target_group_arns : {
#           key         = "${client_name}-${md5(tg_arn)}"
#           client_name = client_name
#           tg_arn      = tg_arn
#         }
#       ]
#     ]) : pair.key => pair
#   }

#   autoscaling_group_name = module.client_eks_clusters[each.value.client_name].node_group_asg_names["primary"]
#   lb_target_group_arn    = each.value.tg_arn
# }
resource "aws_autoscaling_attachment" "alb_target_groups" {
  for_each = {
    for pair in flatten([
      for client_name, alb in module.client_alb : [
        for tg_key, tg_arn in alb.target_group_map : {
          key         = "${client_name}-${tg_key}"   
          client_name = client_name
          tg_arn      = tg_arn                       
        }
      ]
    ]) : pair.key => pair
  }

  autoscaling_group_name = module.client_eks_clusters[each.value.client_name].node_group_asg_names["primary"]
  lb_target_group_arn    = each.value.tg_arn
}
# ==============================================================================
# WAF Web ACLs (Internet-Facing ALBs Only)
# ==============================================================================
# FIX: for_each filter uses try(config.alb.enabled, false) and
# try(config.alb.enable_waf, false) to safely handle null alb blocks.

resource "aws_wafv2_web_acl" "client_waf" {
  for_each = {
    for name, config in local.enabled_alb_clients : name => config
    if try(config.alb.enable_waf, false) && contains(["internet-facing", "both"], try(config.alb.type, "internal"))
  }

  name  = "${each.key}-${var.environment}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

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
    module.tags.minimal_tags,
    {
      Name       = "${each.key}-${var.environment}-waf"
      ClientName = each.key
      Resource   = "WAF"
    }
  )
}
