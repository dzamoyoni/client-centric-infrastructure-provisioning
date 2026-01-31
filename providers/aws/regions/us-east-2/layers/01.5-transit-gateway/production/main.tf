# ============================================================================
# Layer 01.5: Transit Gateway - Centralized Network Hub
# ============================================================================
# Purpose: Centralized routing for all VPCs with egress to Egress VPC
# Architecture: Hub-and-spoke with centralized NAT Gateway egress
# Dependencies: Layer 01 (Foundation - VPCs must exist)
# Cost Savings: ~53-70% vs NAT-per-VPC ($126/month vs $270/month for 3 clients)
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
    bucket = "terraform-state-${var.region}-${var.environment}"
    key    = "${var.region}/01-foundation/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  # Sanitize organization name for resource naming (remove spaces)
  project_name = replace(lower(data.terraform_remote_state.foundation.outputs.organization_name), " ", "-")
  
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
# Tagging Module
# ============================================================================

module "tags" {
  source = "../../../../../../../modules/tagging"
  
  # Core identification
  organization_name = local.project_name
  environment       = var.environment
  layer_name        = "transit"
  region            = var.region
  
  # Contact and ownership
  contact_email = var.contact_email
  owner         = "Platform-Engineering"
  
  # Cost management
  cost_center              = "Infrastructure"
  cost_optimization_enabled = "true"
  
  # Operational
  critical_infrastructure = "true"
  security_level          = "High"
  monitoring_level        = "Enhanced"
  
  # Layer-specific
  layer_purpose = "Centralized Transit Gateway for Multi-VPC Routing"
}

# ============================================================================
# Transit Gateway
# ============================================================================

module "transit_gateway" {
  source = "../../../../../../../modules/transit-gateway"
  
  name        = "${local.project_name}-tgw-${var.region}"
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
          Name   = "${local.project_name}-tgw-attach-egress"
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
          Name       = "${local.project_name}-${client_name}-tgw-attach"
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
        Name    = "${local.project_name}-tgw-rt-spoke"
        Purpose = "Routes traffic from spokes to Egress VPC"
      }
    }
    
    # Egress route table (for Egress VPC)
    egress = {
      description = "Route table for Egress VPC"
      tags = {
        Name    = "${local.project_name}-tgw-rt-egress"
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
# EXCEPT VPN-enabled clients (they use VPN Gateway for routing)
#
# When a new client is added:
#   1. Layer 01 creates VPC + route tables
#   2. Layer 01.5 reads outputs and automatically creates routes
#   3. New client immediately has internet access via TGW → Egress VPC
#
# VPN-Enabled Clients:
#   - VPN Gateway route propagation handles their routing (Layer 01)
#   - On-premises CIDR → VPN Gateway (automatic via route propagation)
#   - Internet 0.0.0.0/0 → Can be manually added if needed
#   - This layer SKIPS them to avoid route conflicts
#
# Supports multiple route tables per client (typically one per AZ)

locals {
  # Get list of VPN-enabled clients from Layer 01
  # These clients manage their own routing via VPN Gateway route propagation
  vpn_enabled_clients = try(data.terraform_remote_state.foundation.outputs.vpn_enabled_clients, [])
  
  # Flatten client route tables into a single map for for_each
  # Format: { "client-a-0" => "rtb-xxx", "client-a-1" => "rtb-yyy" }
  # EXCLUDE VPN-enabled clients - they handle routing via VPN Gateway
  client_route_tables = {
    for pair in flatten([
      for client_name, route_table_ids in data.terraform_remote_state.foundation.outputs.client_private_route_table_ids : [
        for idx, rt_id in route_table_ids : {
          key            = "${client_name}-rt-${idx}"
          client_name    = client_name
          route_table_id = rt_id
        }
        # Skip VPN-enabled clients - VPN Gateway manages their routing
        if !contains(local.vpn_enabled_clients, client_name)
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
