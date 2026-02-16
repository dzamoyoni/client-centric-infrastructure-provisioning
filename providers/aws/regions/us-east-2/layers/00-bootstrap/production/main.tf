# ============================================================================
# Layer 00: Bootstrap - S3 State & Observability Infrastructure
# ============================================================================
# Purpose: Creates foundational S3 buckets for:
#   1. Terraform state storage (for all layers)
#   2. Per-client observability buckets (logs, metrics, traces)
#   3. IAM roles for observability services
#
# Dependencies: None (bootstrap layer runs first)
# Client config: Centralized in ROOT /clients.auto.tfvars
# Deploy: terraform apply -var-file="../../../../../../clients.auto.tfvars"
# Backend: Local (cannot use S3 backend for bootstrap layer - chicken-egg problem)
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy    = "Terraform"
      Layer        = "bootstrap"
      Environment  = var.environment
      Region       = var.region
      Organization = var.organization_name
    }
  }
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  # Enabled clients from CENTRALIZED ROOT /clients.auto.tfvars
  enabled_clients = { for k, v in var.clients : k => v if v.enabled }

  # Account information
  account_id = data.aws_caller_identity.current.account_id

  # Common naming prefix
  resource_prefix = "${var.organization_name}-${var.environment}"

  # Tags for client-specific resources (sanitized for AWS/LocalStack)
  client_tags = {
    for name, config in local.enabled_clients : name => {
      Client       = name
      ClientCode   = config.client_code
      ClientTier   = config.tier
      Industry     = replace(config.metadata.industry, " ", "-")
      CostCenter   = config.metadata.cost_center
      BusinessUnit = replace(config.metadata.business_unit, " ", "-")
      Compliance   = join("+", config.metadata.compliance)  # AWS allows + in tag values
    }
  }

  # Sanitized tags for AWS/LocalStack compatibility
  # Removes special characters and ensures valid tag values
  sanitized_standard_tags = {
    for k, v in module.tags.standard_tags :
    k => replace(
      replace(
        replace(
          replace(
            replace(
              replace(v, " ", "-"),
            "&", "and"),
          ":", "-"),
        "/", "-"),
      "@", "-"),
    ".", "-")
    if v != "" && v != null  # Filter out empty values
  }
}

# ============================================================================
# Layer Metadata - From Shared Config Module
# ============================================================================

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "00-bootstrap"
}

# ============================================================================
# Tagging Configuration 
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"

  # Core identifiers
  organization_name = var.organization_name
  environment       = var.environment
  region            = var.region

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
}
