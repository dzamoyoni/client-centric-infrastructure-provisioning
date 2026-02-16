# ============================================================================
#  Observability Layer - Per-Client Architecture
# ============================================================================
# Comprehensive observability stack deployed to each client's dedicated EKS cluster:
# - Per-Client Isolation: Each client gets own Prometheus, Grafana, Loki, Tempo
# - S3 Storage Backend: Observability data stored in client-specific S3 buckets
# - Production HA: Multi-replica setup with anti-affinity per client
# - Complete Isolation: No cross-client data or metrics sharing
# Client config: Centralized in ROOT /clients.auto.tfvars
# Deploy: terraform apply -var-file="../../../../../../clients.auto.tfvars"
# ============================================================================

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  backend "s3" {
    # Backend configuration loaded from file
  }
}

# ============================================================================
# Data Sources - Integration with Existing Layers
# ============================================================================

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/01-foundation/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/02-platform/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

data "terraform_remote_state" "cluster_services" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/05-cluster-services/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

# AWS Account and Region Information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# Layer Metadata - From Shared Config Module
# ============================================================================

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "06-observability"
}

# ============================================================================
# Tagging Configuration
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core configuration
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
  
  # Observability-specific
  data_retention = "90-days"
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  region = var.region

  # Use minimal_tags to stay under AWS 50-tag limit
  default_tags {
    tags = module.tags.minimal_tags
  }
}

# ============================================================================
# Local Variables - Per-Client Configuration
# ============================================================================

locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs = data.terraform_remote_state.foundation.outputs.client_vpcs
  
  # Platform layer outputs - per-client EKS clusters
  client_clusters = data.terraform_remote_state.platform.outputs.client_clusters
  
  # Filter enabled clients from CENTRALIZED ROOT /clients.auto.tfvars
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled
  }
  
  # Validate all enabled clients have clusters
  missing_clusters = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_clusters), name)
  ]

  # Standard tags for all resources
  standard_tags = module.tags.standard_tags
}

# ============================================================================
# S3 Buckets for Observability Data - Reference Existing Buckets
# ============================================================================

# Reference existing Logs S3 Bucket
data "aws_s3_bucket" "logs" {
  bucket = "${var.region}-${var.environment}-logs"
}

# Reference existing Traces S3 Bucket
data "aws_s3_bucket" "traces" {
  bucket = "${var.region}-${var.environment}-traces"
}

# Reference existing Metrics S3 Bucket
data "aws_s3_bucket" "metrics" {
  bucket = "${var.region}-${var.environment}-metrics"
}

# ============================================================================
# Per-Client Observability Stack
# ============================================================================

module "client_observability" {
  source   = "../../../../../../../modules/observability-per-client"
  for_each = local.enabled_clients
  
  # Client identification
  client_name   = each.key
  client_tier   = each.value.tier
  client_code   = each.value.client_code
  cost_center   = each.value.metadata.cost_center
  business_unit = each.value.metadata.business_unit
  
  # EKS cluster configuration
  cluster_name               = local.client_clusters[each.key].cluster_name
  cluster_endpoint           = local.client_clusters[each.key].cluster_endpoint
  cluster_ca_certificate     = local.client_clusters[each.key].cluster_certificate_authority_data
  oidc_provider_arn          = local.client_clusters[each.key].oidc_provider_arn
  oidc_provider_url          = replace(local.client_clusters[each.key].oidc_provider_arn, "/^.*oidc-provider\\//", "")
  
  # Network configuration
  vpc_id       = local.client_vpcs[each.key].vpc_id
  region       = var.region
  # project_name removed - using client-centric naming
  environment  = var.environment
  
  # S3 storage configuration
  shared_logs_bucket        = data.aws_s3_bucket.logs.id
  shared_logs_bucket_arn    = data.aws_s3_bucket.logs.arn
  shared_traces_bucket      = data.aws_s3_bucket.traces.id
  shared_traces_bucket_arn  = data.aws_s3_bucket.traces.arn
  shared_metrics_bucket     = data.aws_s3_bucket.metrics.id
  shared_metrics_bucket_arn = data.aws_s3_bucket.metrics.arn
  
  # Prometheus configuration (tier-based)
  prometheus_retention      = var.prometheus_retention
  prometheus_retention_size = var.prometheus_retention_size
  prometheus_storage        = each.value.tier == "premium" ? "100Gi" : "50Gi"
  prometheus_replicas       = each.value.tier == "premium" ? 2 : 1
  
  # Loki configuration (tier-based retention)
  loki_retention_days = each.value.tier == "premium" ? 30 : 7
  
  # Tempo configuration (tier-based retention)
  tempo_retention_hours = each.value.tier == "premium" ? 336 : 168  # 14 days vs 7 days
  
  # Grafana configuration
  grafana_admin_password = var.grafana_admin_password
  grafana_storage        = each.value.tier == "premium" ? "50Gi" : "20Gi"
  
  # Alerting configuration (per-client)
  alert_email       = var.alert_email
  slack_webhook_url = var.slack_webhook_url
  
  # Feature flags
  enable_fluent_bit    = true
  enable_loki          = true
  enable_tempo         = true
  enable_node_exporter = true
  
  # Tags
  tags = merge(local.standard_tags, {
    Client       = each.key
    ClientTier   = each.value.tier
    ClientCode   = each.value.client_code
    CostCenter   = each.value.metadata.cost_center
    BusinessUnit = each.value.metadata.business_unit
  })
}
