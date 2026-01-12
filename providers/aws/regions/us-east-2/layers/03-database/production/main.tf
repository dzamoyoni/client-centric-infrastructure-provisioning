# ============================================================================
# Layer 3: Database Layer - US-East-2 Production
# ============================================================================
# High-Availability PostgreSQL databases with master-replica setup for multi-client architecture
# Provides dedicated, secured database instances with enterprise-grade features:
# - Master-Replica PostgreSQL with automatic replication
# - Multi-volume storage strategy (data, WAL, backup)
# - Comprehensive monitoring and alerting
# - Network isolation and security hardening
# - Cross-AZ deployment for high availability
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration loaded from backend.hcl file
  backend "s3" {}
}

# TAGGING STRATEGY: Provider-level default tags for consistency
# All AWS resources will automatically inherit tags from provider configuration
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      # Core identification
      Project         = "${var.region}-${var.environment}"
      Environment     = var.environment
      Region          = var.region
      
      # Operational
      ManagedBy       = "Terraform"
      Layer           = "03-Database"
      DeploymentPhase = "Layer-3"
      
      # Governance
      CriticalInfra   = "true"
      BackupRequired  = "true"
      SecurityLevel   = "High"
      
      # Cost Management
      CostCenter      = "IT-Infrastructure"
      BillingGroup    = "Platform-Engineering"
      
      # Platform specific
      ClusterRole     = "Primary"
      PlatformType    = "Database"
    }
  }
}

# DATA SOURCES - Foundation and Platform Layer Outputs
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

# DATA SOURCES - Current AWS account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# DATA SOURCES - EKS subnet CIDR blocks for client-specific database access
data "aws_subnet" "client_eks" {
  for_each = toset(flatten([
    for client_name, config in var.clients : 
      try(data.terraform_remote_state.foundation.outputs.client_vpcs[client_name].eks_subnet_ids, [])
      if config.enabled
  ]))
  id = each.value
}

# LOCALS - Per-Client VPC Configuration
locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs        = data.terraform_remote_state.foundation.outputs.client_vpcs
  availability_zones = data.terraform_remote_state.foundation.outputs.availability_zones
  
  # Platform layer outputs - per-client EKS clusters
  client_clusters = data.terraform_remote_state.platform.outputs.client_clusters
  
  # Filter enabled clients only
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled
  }
  
  # Validate all enabled clients have VPCs and clusters
  missing_vpcs = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_vpcs), name)
  ]
  
  missing_clusters = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_clusters), name)
  ]
  
  # Build per-client database configuration
  client_database_config = {
    for client_name, config in local.enabled_clients : client_name => {
      # Client's dedicated VPC
      vpc_id     = local.client_vpcs[client_name].vpc_id
      vpc_cidr   = local.client_vpcs[client_name].vpc_cidr
      
      # Database subnets for HA deployment
      database_subnet_ids = local.client_vpcs[client_name].database_subnet_ids
      master_subnet_id    = local.client_vpcs[client_name].database_subnet_ids[0]
      replica_subnet_id   = length(local.client_vpcs[client_name].database_subnet_ids) > 1 ? local.client_vpcs[client_name].database_subnet_ids[1] : local.client_vpcs[client_name].database_subnet_ids[0]
      
      # EKS subnet IDs for access control
      eks_subnet_ids = local.client_vpcs[client_name].eks_subnet_ids
      
      # Get EKS CIDR blocks from subnet IDs
      eks_cidr_blocks = [
        for subnet_id in local.client_vpcs[client_name].eks_subnet_ids :
        data.aws_subnet.client_eks[subnet_id].cidr_block
      ]
      
      # Database security group from VPC
      database_security_group_id = local.client_vpcs[client_name].database_security_group_id
      
      # Database credentials
      db_password          = try(var.database_passwords[client_name], "")
      replication_password = try(var.replication_passwords[client_name], "")
      
      # Client metadata
      tier        = config.tier
      client_code = config.client_code
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
      condition     = length(local.missing_clusters) == 0
      error_message = "Missing EKS clusters from platform layer for clients: ${join(", ", local.missing_clusters)}. Ensure platform layer is applied."
    }
    
    precondition {
      condition     = length(local.enabled_clients) > 0
      error_message = "No enabled clients configured. Check clients.auto.tfvars."
    }
    
    precondition {
      condition = alltrue([
        for name, config in local.client_database_config :
        length(config.database_subnet_ids) >= 1
      ])
      error_message = "Some clients do not have database subnets. Check foundation layer."
    }
  }
  
  triggers = {
    foundation_vpcs = md5(jsonencode({
      for name in keys(local.enabled_clients) : name => local.client_vpcs[name].vpc_id
    }))
    platform_clusters = md5(jsonencode({
      for name in keys(local.enabled_clients) : name => local.client_clusters[name].cluster_name
    }))
    database_config = md5(jsonencode({
      # project_name removed - using client-centric naming
      environment  = var.environment
      region       = var.region
      clients      = local.enabled_clients
    }))
  }
}

# ============================================================================
# HIGH-AVAILABILITY POSTGRESQL DATABASES - DYNAMIC CLIENT PROVISIONING
# ============================================================================
# Databases are provisioned dynamically based on enabled clients in clients.auto.tfvars
# Each client gets isolated Master/Replica HA setup with dedicated subnets

module "client_postgres" {
  for_each = local.enabled_clients
  
  source = "../../../../../../../modules/postgres-ec2"

  # Client identification
  client_name = each.key
  environment = var.environment

  # Network configuration from foundation layer (dynamic per client)
  vpc_id                 = local.client_database_config[each.key].vpc_id
  master_subnet_id       = local.client_database_config[each.key].master_subnet_id
  replica_subnet_id      = local.client_database_config[each.key].replica_subnet_id
  
  # SECURITY: Only allow access from client's own EKS subnets for isolation
  allowed_cidr_blocks    = local.client_database_config[each.key].eks_cidr_blocks
  management_cidr_blocks = var.management_cidr_blocks
  monitoring_cidr_blocks = local.client_database_config[each.key].eks_cidr_blocks

  # Instance configuration
  ami_id                = var.postgres_ami_id
  key_name              = var.key_name
  master_instance_type  = var.master_instance_type
  replica_instance_type = var.replica_instance_type

  # Database configuration (dynamic per client)
  database_name        = "${replace(each.key, "-", "_")}_db"
  database_user        = "${replace(each.key, "-", "_")}_user"
  database_password    = local.client_database_config[each.key].db_password
  replication_password = local.client_database_config[each.key].replication_password

  # Storage configuration
  data_volume_size   = var.data_volume_size
  wal_volume_size    = var.wal_volume_size
  backup_volume_size = var.backup_volume_size

  # Enterprise features
  enable_replica             = true
  enable_monitoring          = true
  enable_encryption          = true
  enable_deletion_protection = true
  backup_retention_days      = each.value.storage.backup_retention_days

  # Dynamic tags based on client configuration
  tags = {
    Client         = each.key
    ClientTier     = each.value.tier
    Purpose        = "${each.key}-database"
    DataClass      = "restricted"
    BackupSchedule = "daily"
    Industry       = each.value.metadata.industry
    CostCenter     = each.value.metadata.cost_center
  }

  depends_on = [null_resource.cross_layer_validation]
}

