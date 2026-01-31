# ============================================================================
# Layer 00: Bootstrap - S3 State & Observability Infrastructure
# ============================================================================
# Purpose: Creates foundational S3 buckets for:
#   1. Terraform state storage (for all layers)
#   2. Per-client observability buckets (logs, metrics, traces)
#   3. IAM roles for observability services
#
# Dependencies: None (bootstrap layer runs first)
# Deploys to: AWS us-east-2
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
  # Enabled clients (from clients.auto.tfvars)
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
# Tagging Module (Industrial Standards)
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"

  # Core identifiers
  organization_name = var.organization_name
  environment       = var.environment
  region            = var.region
  layer_name        = "bootstrap"
  layer_purpose     = "S3 State & Observability Buckets"

  # Infrastructure metadata
  terraform_module = "layers/00-bootstrap"
  account_id       = local.account_id
  provisioned_by   = "Terraform"

  # Operational tags for bootstrap layer
  dr_tier        = var.dr_tier
  rpo            = var.rpo
  rto            = var.rto
  resource_type  = var.resource_type
  security_level = var.security_level

  # Cost and compliance
  cost_center         = var.cost_center
  business_unit       = var.business_unit
  owner               = var.owner
  contact_email       = var.contact_email
  backup_required     = var.backup_required
  data_classification = var.data_classification

  # Bootstrap-specific tags
  critical_infrastructure = var.critical_infrastructure
  deployment_phase        = var.deployment_phase
}
