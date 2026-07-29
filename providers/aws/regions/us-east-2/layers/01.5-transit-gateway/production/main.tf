# ============================================================================
# Layer 01.5: Transit Gateway - Centralized Network Hub
# ============================================================================
# Purpose: Centralized routing for all VPCs with egress to Egress VPC
# Architecture: Hub-and-spoke with centralized NAT Gateway egress
# Dependencies: Layer 01 (Foundation - VPCs must exist)
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
  }
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      Environment   = var.environment
      ManagedBy     = "Terraform"
      Layer         = "01.5-transit-gateway"
      Region        = var.region
      CostCenter    = "Infrastructure"
      Purpose       = "Centralized Transit Gateway Hub"
    }
  }
}

# ============================================================================
# Data Sources - Read Foundation Layer Outputs
# ============================================================================

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "terraform-state-${var.region}-${var.environment}-myorg"
    key    = "${var.region}/01-foundation/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  # VPC IDs from Layer 01 (client-centric architecture - no foundation VPC)
  egress_vpc_id  = data.terraform_remote_state.foundation.outputs.egress_vpc_id
  client_vpc_ids = data.terraform_remote_state.foundation.outputs.client_vpc_ids
  
  # Subnet IDs for TGW attachments (one subnet per AZ in each VPC)
  egress_private_subnet_ids = data.terraform_remote_state.foundation.outputs.egress_private_subnet_ids
  
  # Client subnet IDs (EKS subnets for TGW attachment)
  client_eks_subnet_ids = data.terraform_remote_state.foundation.outputs.client_eks_subnet_ids
  
  # VPC CIDRs for routing
  egress_vpc_cidr  = data.terraform_remote_state.foundation.outputs.egress_vpc_cidr
  client_vpc_cidrs = data.terraform_remote_state.foundation.outputs.client_vpc_cidrs
}

# ============================================================================
# Layer Metadata - From Shared Config Module
# ============================================================================

module "layer_config" {
  source   = "../../../../../../../modules/shared-config"
  layer_id = "01.5-transit-gateway"
}

# ============================================================================
# Tagging Configuration
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core identification
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

# ============================================================================
# Transit Gateway
# ============================================================================

module "transit_gateway" {
  source = "../../../../../../../modules/transit-gateway"
  
  name        = "tgw-${var.region}"
  description = "Centralized Transit Gateway for multi-VPC architecture with egress to Egress VPC"
  # Use minimal_tags to stay under AWS 50-tag limit
  common_tags = module.tags.minimal_tags
  
  # Transit Gateway Configuration
  amazon_side_asn                 = var.transit_gateway_asn
  default_route_table_association = false  # Manual control over route tables
  default_route_table_propagation = false  # Manual control over propagation
  dns_support                     = true
  vpn_ecmp_support                = true
  auto_accept_shared_attachments  = false
  
  # VPC Attachments (client-centric: only egress + client VPCs)
  vpc_attachments = merge(
    # Egress VPC attachment
    {
      egress = {
        vpc_id     = local.egress_vpc_id
        subnet_ids = local.egress_private_subnet_ids
        transit_gateway_default_route_table_association = false
        transit_gateway_default_route_table_propagation = false
        tags = {
          Name   = "tgw-attach-egress-${var.region}"
          VPCType = "Egress"
        }
      }
    },
    
    # Client VPC attachments
    {
      for client_name, vpc_id in local.client_vpc_ids :
      client_name => {
        vpc_id     = vpc_id
        subnet_ids = local.client_eks_subnet_ids[client_name]
        transit_gateway_default_route_table_association = false
        transit_gateway_default_route_table_propagation = false
        tags = {
          Name       = "${client_name}-tgw-attach-${var.region}"
          VPCType    = "Client"
          ClientName = client_name
        }
      }
    }
  )
  
  # Route Tables
  route_tables = {
    # Spoke route table (for Foundation and Client VPCs)
    spoke = {
      description = "Route table for spoke VPCs (Foundation + Clients)"
      tags = {
        Name    = "tgw-rt-spoke-${var.region}"
        Purpose = "Routes traffic from spokes to Egress VPC"
      }
    }
    
    # Egress route table (for Egress VPC)
    egress = {
      description = "Route table for Egress VPC"
      tags = {
        Name    = "tgw-rt-egress-${var.region}"
        Purpose = "Routes return traffic from Egress VPC to spokes"
      }
    }
  }
  
  # Route Table Associations (client-centric: no foundation VPC)
  route_table_associations = merge(
    # Egress VPC → Egress route table
    {
      egress = {
        vpc_attachment_key = "egress"
        route_table_key    = "egress"
      }
    },
    
    # Client VPCs → Spoke route table
    {
      for client_name in keys(local.client_vpc_ids) :
      client_name => {
        vpc_attachment_key = client_name
        route_table_key    = "spoke"
      }
    }
  )
  
  # Route Table Propagations (client-centric: propagate only client VPCs)
  route_table_propagations = {
    for client_name in keys(local.client_vpc_ids) :
    "${client_name}_to_egress" => {
      vpc_attachment_key = client_name
      route_table_key    = "egress"
    }
  }
  
  # Static Routes
  static_routes = {
    # Default route from spoke VPCs → Egress VPC
    default_to_egress = {
      destination_cidr_block = "0.0.0.0/0"
      vpc_attachment_key     = "egress"
      route_table_key        = "spoke"
    }
  }
  
  # Flow Logs (optional, enabled for production)
  enable_flow_logs        = var.enable_transit_gateway_flow_logs
  flow_log_retention_days = var.transit_gateway_flow_log_retention_days
  
  # Cross-account sharing (disabled by default)
  enable_cross_account_sharing = false
}

# ============================================================================
# VPC Route Table Updates - Automatic Route Injection
# ============================================================================
# Purpose: Add default routes (0.0.0.0/0 → TGW) to all VPC route tables
# 
# Why here and not Layer 01?
#   - Avoids circular dependency (VPC needs TGW ID, TGW needs VPC ID)
#   - Transit Gateway must exist before routes can be created
#
# Dynamic Behavior:
#   - NEW CLIENT ADDED: Routes automatically created when Layer 01.5 is applied
#   - CLIENT REMOVED: Routes automatically deleted when Layer 01.5 is applied
#   - NO MANUAL INTERVENTION REQUIRED
#
# Route Flow:
#   Client VPC Private Subnet → Route Table (0.0.0.0/0 → TGW) → Transit Gateway
#   → Spoke Route Table (0.0.0.0/0 → Egress VPC) → Egress VPC → NAT → Internet
# ============================================================================

# ----------------------------------------------------------------------------
# Client VPC Routes to Transit Gateway (DYNAMIC)
# ----------------------------------------------------------------------------
# Automatically creates routes for ALL enabled clients from Layer 01
# INCLUDING VPN-enabled clients.
#
# VPN + TGW coexistence:
#   - VPN Gateway propagates on-premises CIDRs (e.g., 10.x.x.x/16 → VPN GW)
#   - TGW provides internet egress (0.0.0.0/0 → TGW → Egress VPC → NAT)
#   - No conflict: VPN handles specific on-prem routes, TGW handles default route
#   - AWS route tables support both simultaneously (more-specific routes win)
#
# When a new client is added:
#   1. Layer 01 creates VPC + route tables
#   2. Layer 01.5 reads outputs and automatically creates routes
#   3. New client immediately has internet access via TGW → Egress VPC
#
# Supports multiple route tables per client (typically one per AZ)

locals {
  # Get list of VPN-enabled clients from Layer 01 (for reference/outputs only)
  vpn_enabled_clients = try(data.terraform_remote_state.foundation.outputs.vpn_enabled_clients, [])
  
  # Flatten client route tables into a single map for for_each
  # Format: { "client-a-0" => "rtb-xxx", "client-a-1" => "rtb-yyy" }
  # ALL clients get TGW routes — VPN clients also need internet egress via TGW
  client_route_tables = {
    for pair in flatten([
      for client_name, route_table_ids in data.terraform_remote_state.foundation.outputs.client_private_route_table_ids : [
        for idx, rt_id in route_table_ids : {
          key            = "${client_name}-rt-${idx}"
          client_name    = client_name
          route_table_id = rt_id
        }
      ]
    ]) : pair.key => pair
  }
}





resource "aws_route" "client_private_to_tgw" {
  for_each = local.client_route_tables
  
  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
  
  depends_on = [module.transit_gateway]
  
  lifecycle {
    create_before_destroy = true
  }
  
  # Optional: Add timeouts for large deployments
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# ----------------------------------------------------------------------------
# EKS Subnet Routes to Transit Gateway (DYNAMIC)
# ----------------------------------------------------------------------------
# Adds routes to EKS subnets for pod egress traffic
# Pods → EKS Subnet Route Table → TGW → Egress VPC → NAT → Internet

locals {
  # Flatten EKS route tables (if separate from private subnets)
  client_eks_route_tables = {
    for pair in flatten([
      for client_name, route_table_ids in try(data.terraform_remote_state.foundation.outputs.client_eks_route_table_ids, {}) : [
        for idx, rt_id in route_table_ids : {
          key            = "${client_name}-eks-rt-${idx}"
          client_name    = client_name
          route_table_id = rt_id
        }
      ]
    ]) : pair.key => pair
  }
}

resource "aws_route" "client_eks_to_tgw" {
  for_each = local.client_eks_route_tables
  
  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
  
  depends_on = [module.transit_gateway]
  
  lifecycle {
    create_before_destroy = true
  }
  
  timeouts {
    create = "5m"
    delete = "5m"
  }
}


locals {
  egress_private_route_table_ids = data.terraform_remote_state.foundation.outputs.egress_private_route_table_ids
  
  # Create a flat map: one entry per (route_table, client_cidr) pair
  egress_return_routes = {
    for pair in flatten([
      for rt_id in local.egress_private_route_table_ids : [
        for client_name, cidr in local.client_vpc_cidrs : {
          key            = "${client_name}-via-rt-${rt_id}"
          route_table_id = rt_id
          cidr           = cidr
        }
      ]
    ]) : pair.key => pair
  }
}


resource "aws_route" "egress_to_client_vpcs" {
  for_each = local.egress_return_routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  depends_on = [module.transit_gateway]

  timeouts {
    create = "5m"
    delete = "5m"
  }
}
# ----------------------------------------------------------------------------
# Database Subnet Routes to Transit Gateway (DYNAMIC)
# ----------------------------------------------------------------------------
# Adds routes to database subnets for outbound connections
# Database → DB Subnet Route Table → TGW → Egress VPC → NAT → Internet
# Use case: apt updates, replication to external systems, backups to S3 via NAT

locals {
  # Flatten database route tables
  client_db_route_tables = {
    for pair in flatten([
      for client_name, route_table_ids in try(data.terraform_remote_state.foundation.outputs.client_database_route_table_ids, {}) : [
        for idx, rt_id in route_table_ids : {
          key            = "${client_name}-db-rt-${idx}"
          client_name    = client_name
          route_table_id = rt_id
        }
      ]
    ]) : pair.key => pair
  }
}

resource "aws_route" "client_database_to_tgw" {
  for_each = local.client_db_route_tables
  
  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.transit_gateway_id
  
  depends_on = [module.transit_gateway]
  
  lifecycle {
    create_before_destroy = true
  }
  
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# ----------------------------------------------------------------------------
# Egress VPC Routing
# ----------------------------------------------------------------------------
# Egress VPC private subnets already have default route to NAT Gateway
# Traffic from TGW arrives via attachment and follows existing NAT route:
#   TGW → Egress VPC Private Subnet → Route Table (0.0.0.0/0 → NAT) → NAT GW → IGW
#
# Return traffic uses Transit Gateway route propagation:
#   Internet → IGW → NAT GW → Private Subnet → TGW (client CIDR → attachment) → Client VPC
