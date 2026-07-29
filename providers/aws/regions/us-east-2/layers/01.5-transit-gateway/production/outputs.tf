# ============================================================================
# Layer 01.5: Transit Gateway - Outputs
# ============================================================================

output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = module.transit_gateway.transit_gateway_id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway"
  value       = module.transit_gateway.transit_gateway_arn
}

output "transit_gateway_owner_id" {
  description = "Owner ID of the Transit Gateway"
  value       = module.transit_gateway.transit_gateway_owner_id
}

# ============================================================================
# VPC Attachments
# ============================================================================

output "vpc_attachment_ids" {
  description = "Map of VPC attachment IDs by VPC name"
  value       = module.transit_gateway.vpc_attachment_ids
}

output "egress_vpc_attachment_id" {
  description = "Transit Gateway attachment ID for Egress VPC"
  value       = module.transit_gateway.vpc_attachment_ids["egress"]
}

output "client_vpc_attachment_ids" {
  description = "Map of Transit Gateway attachment IDs for client VPCs"
  value = {
    for client_name in keys(local.client_vpc_ids) :
    client_name => module.transit_gateway.vpc_attachment_ids[client_name]
  }
}

# ============================================================================
# Route Tables
# ============================================================================

output "spoke_route_table_id" {
  description = "Transit Gateway route table ID for spoke VPCs"
  value       = module.transit_gateway.route_table_ids["spoke"]
}

output "egress_route_table_id" {
  description = "Transit Gateway route table ID for egress VPC"
  value       = module.transit_gateway.route_table_ids["egress"]
}

# ============================================================================
# Cost Information
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for Transit Gateway infrastructure"
  value = {
    transit_gateway = "$36/month (hourly charge + attachment fees)"
    vpc_attachments = "${length(module.transit_gateway.vpc_attachment_ids)} attachments (included in TGW cost)"
    data_transfer   = "$0.02/GB for inter-VPC traffic via TGW"
    total_fixed     = "$36/month + variable data transfer charges"
    note            = "Add Egress VPC NAT Gateway costs: $90/month (2 NAT GW HA) or $45/month (1 NAT GW)"
  }
}

# ============================================================================
# Network Information
# ============================================================================

output "network_topology" {
  description = "Network topology summary"
  value = {
    architecture          = "Hub-and-Spoke with Centralized Egress (Client-Centric)"
    transit_gateway_asn   = var.transit_gateway_asn
    spoke_vpcs            = length(local.client_vpc_ids)  # Client VPCs only
    egress_vpc            = "Centralized NAT Gateway"
    routing_model         = "Client VPCs → TGW → Egress VPC → NAT → Internet"
    flow_logs_enabled     = var.enable_transit_gateway_flow_logs
  }
}

# ============================================================================
# Automatic Route Management - Visibility & Audit
# ============================================================================

output "routes_created" {
  description = "Summary of routes automatically created by Layer 01.5"
  value = {
    # Client private subnet routes
    client_private_routes = {
      count = length(local.client_route_tables)
      clients = keys({
        for k, v in local.client_route_tables :
        v.client_name => true...
      })
      description = "Default routes (0.0.0.0/0 → TGW) in client private subnets"
    }
    
    # Client EKS subnet routes
    client_eks_routes = {
      count = length(local.client_eks_route_tables)
      clients = keys({
        for k, v in local.client_eks_route_tables :
        v.client_name => true...
      })
      description = "Default routes (0.0.0.0/0 → TGW) in client EKS subnets"
    }
    
    # Client database subnet routes
    client_database_routes = {
      count = length(local.client_db_route_tables)
      clients = keys({
        for k, v in local.client_db_route_tables :
        v.client_name => true...
      })
      description = "Default routes (0.0.0.0/0 → TGW) in client database subnets"
    }
    
    # Total routes managed
    total_routes_managed = length(local.client_route_tables) + length(local.client_eks_route_tables) + length(local.client_db_route_tables)
  }
}




output "client_routing_summary" {
  description = "Per-client routing configuration (automatically managed)"
  value = {
    for client_name in keys(local.client_vpc_ids) :
    client_name => {
      vpc_id = local.client_vpc_ids[client_name]
      tgw_attachment_id = module.transit_gateway.vpc_attachment_ids[client_name]
      route_table_association = "spoke"  # All clients use spoke route table
      internet_egress_path = "VPC → TGW → Egress VPC → NAT Gateway → Internet"
      isolation_status = "ISOLATED - No routes to other client VPCs"
      
      # Route table counts
      private_route_tables = length([
        for k, v in local.client_route_tables :
        k if v.client_name == client_name
      ])
      
      eks_route_tables = length([
        for k, v in local.client_eks_route_tables :
        k if v.client_name == client_name
      ])
      
      database_route_tables = length([
        for k, v in local.client_db_route_tables :
        k if v.client_name == client_name
      ])
    }
  }
}

output "automatic_route_management_info" {
  description = "Information about automatic route management"
  value = {
    dynamic_routing_enabled = true
    new_client_handling = "Routes automatically created when Layer 01.5 is applied after Layer 01"
    removed_client_handling = "Routes automatically destroyed when client is disabled in Layer 01"
    manual_intervention_required = false
    
    workflow = [
      "1. Add client to clients.auto.tfvars",
      "2. Apply Layer 01 (creates VPC + route tables)",
      "3. Apply Layer 01.5 (automatically creates TGW attachment + routes)",
      "4. Client immediately has internet access via centralized egress"
    ]
    
    route_types_managed = [
      "Private subnet routes (0.0.0.0/0 → TGW)",
      "EKS subnet routes (0.0.0.0/0 → TGW)",
      "Database subnet routes (0.0.0.0/0 → TGW)"
    ]
  }
}
