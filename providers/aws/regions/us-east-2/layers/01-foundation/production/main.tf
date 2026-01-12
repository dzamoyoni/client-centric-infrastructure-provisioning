# Foundation Layer - us-east-2 Production
# CRITICAL INFRASTRUCTURE: Per-Client VPCs, Subnets, NAT Gateways, VPN
# DO NOT DELETE OR MODIFY WITHOUT PROPER AUTHORIZATION
#
# PER-CLIENT VPC ARCHITECTURE:
# - Each client gets a dedicated VPC with unique CIDR
# - Complete network isolation between clients
# - Client VPCs defined in cidr-registry.yaml (root of repo)
# - Zero hardcoding - pure data-driven infrastructure
# - Add/remove clients by editing clients.auto.tfvars only

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
# Centralized Tagging Configuration
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core configuration
  environment      = var.environment
  layer_name       = "foundation"
  region           = var.region
  
  # Layer-specific configuration
  layer_purpose    = "VPC and Network Infrastructure"
  deployment_phase = "Phase-1"
  
  # Infrastructure classification
  critical_infrastructure = "true"
  backup_required        = "true"
  security_level         = "High"
  
  # Cost management
  cost_center      = "IT-Infrastructure"
  billing_group    = "Platform-Engineering"
  chargeback_code  = "EST1-FOUNDATION-001"
  
  # Operational settings
  sla_tier           = "Gold"
  monitoring_level   = "Enhanced"
  maintenance_window = "Sunday-02:00-04:00-UTC"
  
  # Governance
  compliance_framework = "SOC2-ISO27001"
  data_classification  = "Internal"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = module.tags.standard_tags
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

module "client_vpcs" {
  for_each = local.enabled_clients
  
  source = "../../../../../../../modules/client-vpc"

  # Client identification
  client_name  = each.key
  environment  = var.environment
  region       = var.region

  # Network configuration from clients.auto.tfvars
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
  
  # Client-specific VPN configuration from clients.auto.tfvars
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
  
  # Generate client-specific tags dynamically
  client_tags = {
    for name, config in local.enabled_clients : name => merge(
      module.tags.standard_tags,
      {
        Client         = name
        ClientCode     = config.client_code
        ClientTier     = config.tier
        VpcCidr        = config.network.vpc_cidr
        TenantType     = "Production"
        Industry       = config.metadata.industry
        CostCenter     = config.metadata.cost_center
        BusinessUnit   = config.metadata.business_unit
        Compliance     = join(",", config.metadata.compliance)
      }
    )
  }
}
