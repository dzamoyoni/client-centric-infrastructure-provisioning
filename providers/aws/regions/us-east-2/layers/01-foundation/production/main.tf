# Foundation Layer
# CRITICAL INFRASTRUCTURE: VPCs, Subnets, NAT Gateways, VPN
#
# PER-CLIENT VPC ARCHITECTURE:
# - Each client gets a dedicated VPC with unique CIDR
# - Complete network isolation between clients
# - Client config centralized in ROOT /clients.auto.tfvars
# - Deploy with: terraform apply -var-file="../../../../../../clients.auto.tfvars"

# ============================================================================
# Foundation Layer - Root Main Configuration
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "01-foundation"
}

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  environment        = var.environment
  region             = var.region
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

  default_tags {
    tags = module.tags.minimal_tags
  }
}

# Dynamic Availability Zone Discovery
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Dynamically pick available AZs (defaulting to 2 for HA)
  availability_zones = slice(data.aws_availability_zones.available.names, 0, min(2, length(data.aws_availability_zones.available.names)))
  
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled
  }
  
  cidr_list      = [for name, config in local.enabled_clients : config.network.vpc_cidr]
  cidr_conflicts = length(local.cidr_list) != length(distinct(local.cidr_list))
  
  common_tags   = module.tags.standard_tags
  critical_tags = module.tags.comprehensive_tags
  
  client_tags = {
    for name, config in local.enabled_clients : name => {
      Client       = name
      ClientCode   = config.client_code
      ClientTier   = config.tier
      VpcCidr      = config.network.vpc_cidr
      Industry     = replace(config.metadata.industry, " ", "-")
      CostCenter   = config.metadata.cost_center
      BusinessUnit = replace(config.metadata.business_unit, " ", "-")
      Compliance   = join("+", config.metadata.compliance)
    }
  }
}

# Per-Client VPCs
module "client_vpcs" {
  for_each = local.enabled_clients
  
  source = "../../../../../../../modules/client-vpc"

  client_name        = each.key
  environment        = var.environment
  region             = var.region
  vpc_cidr           = each.value.network.vpc_cidr
  availability_zones = local.availability_zones
  cluster_name       = "${each.key}-${var.environment}-${var.region}"

  database_ports = each.value.security.database_ports
  custom_ports   = each.value.security.custom_ports
  
  enable_flow_logs        = true
  flow_log_retention_days = 30
  
  enable_nat_gateway = false
  transit_gateway_id = null
  
  common_tags = local.client_tags[each.key]
}

# Per-Client Site-to-Site VPN Connections
module "client_vpn" {
  for_each = {
    for name, config in var.clients : name => config
    if config.enabled && try(config.vpn.enabled, false)
  }
  
  source = "../../../../../../../modules/site-to-site-vpn"
  
  enabled      = true
  client_name  = each.key
  region       = var.region
  
  vpc_id                 = module.client_vpcs[each.key].vpc_id
  client_route_table_ids = module.client_vpcs[each.key].private_route_table_ids
  
  customer_gateway_ip   = each.value.vpn.customer_gateway_ip
  bgp_asn               = each.value.vpn.bgp_asn
  amazon_side_asn       = each.value.vpn.amazon_side_asn
  static_routes_only    = each.value.vpn.static_routes_only
  onprem_cidr_blocks    = [each.value.vpn.local_network_cidr]
  tunnel1_inside_cidr   = each.value.vpn.tunnel1_inside_cidr
  tunnel1_preshared_key = null
  tunnel2_inside_cidr   = each.value.vpn.tunnel2_inside_cidr
  tunnel2_preshared_key = null
  
  enable_vpn_logging     = true
  vpn_log_retention_days = 30
  sns_topic_arn          = try(var.sns_topic_arn, null)
  
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

# Centralized Egress VPC
module "egress_vpc" {
  source = "../../../../../../../modules/egress-vpc"

  project_name       = "Org Name"
  region             = var.region
  vpc_cidr           = "10.255.0.0/16"
  availability_zones = local.availability_zones
  common_tags        = module.tags.standard_tags

  # Pass ALL active client VPC CIDRs dynamically to ensure public RT backroutes exist
  spoke_vpcs_cidrs   = [for c in local.enabled_clients : c.network.vpc_cidr]
  transit_gateway_id = try(var.transit_gateway_id, null)

  enable_high_availability = true
  enable_vpc_endpoints     = true
  enable_flow_logs         = true
  flow_log_retention_days  = 7
}