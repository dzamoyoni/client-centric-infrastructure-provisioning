# Foundation Layer
# CRITICAL INFRASTRUCTURE: VPCs, Subnets, NAT Gateways, VPN
#
# PER-CLIENT VPC ARCHITECTURE:
# - Each client gets a dedicated VPC with unique CIDR
# - Complete network isolation between clients
# - Client config centralized in ROOT /clients.auto.tfvars
# - Deploy with: terraform apply -var-file="../../../../../../clients.auto.tfvars"

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration loaded from backend.hcl file
  # Use: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

# ============================================================================
# Layer Metadata - From Shared Config Module
# ============================================================================
# Single source of truth: modules/shared-config/main.tf

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "01-foundation"
}

# ============================================================================
# Simplified Tagging Configuration (85% reduction)
# ============================================================================
# Layer metadata from shared-config module (no duplication!)
# Common defaults from tagging module

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Required core parameters
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
}

provider "aws" {
  region = var.region

  # Use minimal_tags to stay under AWS 50-tag limit
  # default_tags are automatically applied to ALL resources
  default_tags {
    tags = module.tags.minimal_tags
  }
}

#  DATA SOURCES
data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================================
# PER-CLIENT VPCs - Complete Network Isolation
# ============================================================================
# Each client gets a dedicated VPC with their own CIDR from cidr-registry.yaml
# Includes: VPC, IGW, NAT Gateways, Subnets, Security Groups, VPC Endpoints
# NO SHARED RESOURCES - complete client isolation
#
# CLIENT CONFIG: centralized in ROOT /clients.auto.tfvars
# No more duplicate configs across layers!

module "client_vpcs" {
  for_each = local.enabled_clients
  
  source = "../../../../../../../modules/client-vpc"

  # Client identification
  client_name  = each.key
  environment  = var.environment
  region       = var.region

  # Network configuration from CENTRALIZED ROOT /clients.auto.tfvars
  vpc_cidr           = each.value.network.vpc_cidr
  availability_zones = local.availability_zones

  # EKS cluster name for subnet tagging (client-centric naming)
  cluster_name = "${each.key}-${var.environment}-${var.region}"

  # Security configuration
  database_ports = each.value.security.database_ports
  custom_ports   = each.value.security.custom_ports
  
  # VPC Flow Logs
  enable_flow_logs        = true
  flow_log_retention_days = 30
  
  # Transit Gateway Configuration (NAT disabled - using centralized egress)
  enable_nat_gateway = false
  transit_gateway_id = null  # Set by Layer 01.5 via route resources
  
  # Tags
  common_tags = local.client_tags[each.key]
}
# ============================================================================
# PER-CLIENT VPN CONNECTIONS - Site-to-Site VPN to On-Premises
# ============================================================================
# Creates VPN for each client with vpn.enabled = true
# VPN Gateway attached to client's dedicated VPC
# Routes ONLY to that client's private subnets (complete isolation)
# NO HARDCODED CLIENT NAMES - fully dynamic!

module "client_vpn" {
  # Only create VPN for clients with VPN enabled
  for_each = {
    for name, config in var.clients : name => config
    if config.enabled && try(config.vpn.enabled, false)
  }
  
  source = "../../../../../../../modules/site-to-site-vpn"
  
  enabled      = true
  client_name  = each.key
  region       = var.region
  
  # Client's dedicated VPC
  vpc_id                 = module.client_vpcs[each.key].vpc_id
  client_route_table_ids = module.client_vpcs[each.key].private_route_table_ids
  
  # Client-specific VPN configuration from CENTRALIZED /clients.auto.tfvars
  # NO DEFAULTS - all values must be explicit in tfvars
  customer_gateway_ip = each.value.vpn.customer_gateway_ip
  bgp_asn             = each.value.vpn.bgp_asn
  amazon_side_asn     = each.value.vpn.amazon_side_asn
  static_routes_only  = each.value.vpn.static_routes_only
  onprem_cidr_blocks  = [each.value.vpn.local_network_cidr]
  
  # Tunnel configuration from clients.auto.tfvars
  tunnel1_inside_cidr   = each.value.vpn.tunnel1_inside_cidr
  tunnel1_preshared_key = null  # AWS auto-generates
  tunnel2_inside_cidr   = each.value.vpn.tunnel2_inside_cidr
  tunnel2_preshared_key = null  # AWS auto-generates
  
  enable_vpn_logging     = true
  vpn_log_retention_days = 30
  sns_topic_arn          = try(var.sns_topic_arn, null)
  
  # Client-specific tags
  common_tags = merge(
    local.client_tags[each.key],
    {
      VPNClient      = each.key
      VPNType        = "Site-to-Site"
      OnPremNetwork  = each.value.vpn.local_network_cidr
      VPNDescription = each.value.vpn.description
    }
  )
  
  depends_on = [module.client_vpcs]
}

# ============================================================================
# Egress VPC - Centralized NAT Gateway for All VPCs
# ============================================================================
# Purpose: Centralized internet egress for all VPCs via Transit Gateway
# Architecture: All VPCs route to Transit Gateway → Egress VPC → NAT → Internet

module "egress_vpc" {
  source = "../../../../../../../modules/egress-vpc"
  
  project_name       = "Org Name"  # Organization name
  region             = var.region
  vpc_cidr           = "10.255.0.0/16"  # Dedicated CIDR for egress VPC
  availability_zones = local.availability_zones
  common_tags        = module.tags.standard_tags
  
  # High Availability with 2 NAT Gateways (one per AZ)
  enable_high_availability = true
  
  # VPC Endpoints for cost optimization
  enable_vpc_endpoints = true
  
  # Flow Logs for security monitoring
  enable_flow_logs        = true
  flow_log_retention_days = 7
}

# ============================================================================
# Locals - Client Processing & Tagging
# ============================================================================

locals {
  # Use first 2 AZs for high availability
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  
  # Filter enabled clients only
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled
  }
  
  # CIDR validation - VPC CIDRs must be explicitly provided in clients.auto.tfvars
  # Global uniqueness enforced by cidr-registry.yaml and validate-cidr.sh
  cidr_list = [for name, config in local.enabled_clients : config.network.vpc_cidr]
  cidr_conflicts = length(local.cidr_list) != length(distinct(local.cidr_list))
  
  # Standard tags for all resources in this layer
  common_tags = module.tags.standard_tags
  
  # Comprehensive tags for critical infrastructure
  critical_tags = module.tags.comprehensive_tags
  
  # Generate client-specific tags dynamically (sanitized for AWS)
  # NOTE: Do NOT include minimal_tags here - they're already in provider default_tags
  # This avoids tag duplication and keeps total under 50-tag limit
  client_tags = {
    for name, config in local.enabled_clients : name => {
      Client         = name
      ClientCode     = config.client_code
      ClientTier     = config.tier
      VpcCidr        = config.network.vpc_cidr
      Industry       = replace(config.metadata.industry, " ", "-")
      CostCenter     = config.metadata.cost_center
      BusinessUnit   = replace(config.metadata.business_unit, " ", "-")
      Compliance     = join("+", config.metadata.compliance)
    }
  }
}
