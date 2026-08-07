# ============================================================================
# Foundation Layer Outputs - Per-Client VPC Architecture
# ============================================================================
# Each client has a dedicated VPC with complete network isolation
# Other layers access client-specific resources via: 
#   data.terraform_remote_state.foundation.outputs.client_vpcs["client-name"]
# ============================================================================

# ============================================================================
# Core Infrastructure
# ============================================================================

# ============================================================================
# Foundation Layer - Outputs
# ============================================================================

output "availability_zones" {
  description = "Availability zones used across all client VPCs"
  value       = local.availability_zones
}

output "organization_name" {
  description = "Organization name for resource naming"
  value       = "Org Name"
}

output "client_vpcs" {
  description = "Complete VPC infrastructure per client"
  value = {
    for name, vpc_module in module.client_vpcs : name => {
      vpc_id                     = vpc_module.vpc_id
      vpc_cidr                   = vpc_module.vpc_cidr_block
      public_subnet_ids          = vpc_module.public_subnet_ids
      eks_subnet_ids             = vpc_module.eks_subnet_ids
      database_subnet_ids        = vpc_module.database_subnet_ids
      compute_subnet_ids         = vpc_module.compute_subnet_ids
      eks_security_group_id     = vpc_module.eks_security_group_id
      database_security_group_id = vpc_module.database_security_group_id
      compute_security_group_id = vpc_module.compute_security_group_id
      nat_gateway_ids           = vpc_module.nat_gateway_ids
      nat_gateway_public_ips    = vpc_module.nat_gateway_public_ips
      private_route_table_ids    = vpc_module.private_route_table_ids
      s3_vpc_endpoint_id         = vpc_module.s3_vpc_endpoint_id
      ecr_dkr_vpc_endpoint_id    = vpc_module.ecr_dkr_vpc_endpoint_id
      ecr_api_vpc_endpoint_id    = vpc_module.ecr_api_vpc_endpoint_id
      client_code                = var.clients[name].client_code
      tier                       = var.clients[name].tier
      metadata                   = var.clients[name].metadata
    }
  }
}

output "egress_vpc_id" {
  description = "ID of the centralized Egress VPC"
  value       = module.egress_vpc.vpc_id
}

output "egress_vpc_cidr" {
  description = "CIDR block of the Egress VPC"
  value       = module.egress_vpc.vpc_cidr
}

output "egress_private_subnet_ids" {
  description = "Private subnet IDs in Egress VPC (for Transit Gateway attachment)"
  value       = module.egress_vpc.private_subnet_ids
}

output "egress_public_subnet_ids" {
  description = "Public subnet IDs in Egress VPC (for NAT Gateways)"
  value       = module.egress_vpc.public_subnet_ids
}

output "egress_public_route_table_id" {
  description = "Public Route Table ID in Egress VPC (for return route injection)"
  value       = module.egress_vpc.public_route_table_id
}

output "egress_nat_gateway_ids" {
  description = "NAT Gateway IDs in Egress VPC"
  value       = module.egress_vpc.nat_gateway_ids
}

output "egress_nat_gateway_public_ips" {
  description = "Public IPs of NAT Gateways in Egress VPC"
  value       = module.egress_vpc.nat_gateway_public_ips
}

output "foundation_vpc_id" {
  description = "Foundation VPC ID"
  value       = null
}

output "foundation_vpc_cidr" {
  description = "Foundation VPC CIDR"
  value       = null
}

output "foundation_platform_subnet_ids" {
  description = "Foundation platform subnet IDs"
  value       = []
}

output "foundation_platform_route_table_ids" {
  description = "Foundation platform route table IDs"
  value       = []
}

output "client_vpc_ids" {
  description = "Map of client VPC IDs"
  value = {
    for name, vpc in module.client_vpcs : name => vpc.vpc_id
  }
}

output "client_vpc_cidrs" {
  description = "Map of client VPC CIDR blocks"
  value = {
    for name, config in local.enabled_clients : name => config.network.vpc_cidr
  }
}

output "client_eks_subnet_ids" {
  description = "Map of client EKS subnet IDs"
  value = {
    for name, vpc in module.client_vpcs : name => vpc.eks_subnet_ids
  }
}

output "client_private_route_table_ids" {
  description = "Map of client private route table IDs"
  value = {
    for name, vpc in module.client_vpcs : name => vpc.private_route_table_ids
  }
}

output "egress_private_route_table_ids" {
  description = "Private route table IDs in Egress VPC"
  value       = module.egress_vpc.private_route_table_ids
}

output "client_vpn_connections" {
  description = "VPN connections per client"
  value = {
    for client_name, vpn_module in module.client_vpn : client_name => {
      vpn_connection_id   = vpn_module.vpn_connection_id
      vpn_gateway_id      = vpn_module.vpn_gateway_id
      tunnel1_address     = vpn_module.tunnel1_address
      tunnel2_address     = vpn_module.tunnel2_address
      customer_gateway_ip = var.clients[client_name].vpn.customer_gateway_ip
      local_network       = var.clients[client_name].vpn.local_network_cidr
      description         = var.clients[client_name].vpn.description
    }
  }
}

output "vpn_enabled_clients" {
  description = "List of client names with VPN enabled"
  value = [
    for name, config in var.clients : name
    if config.enabled && try(config.vpn.enabled, false)
  ]
}

output "foundation_summary" {
  description = "Summary of per-client VPC infrastructure deployed"
  value = {
    region              = var.region
    environment         = var.environment
    availability_zones  = local.availability_zones
    total_clients       = length(local.enabled_clients)
    provisioned_clients = keys(local.enabled_clients)
    client_vpcs = {
      for name, config in local.enabled_clients : name => {
        vpc_cidr    = config.network.vpc_cidr
        client_code = config.client_code
        tier        = config.tier
      }
    }
    vpc_flow_logs_enabled = true
    vpc_endpoints_enabled = true
    architecture          = "per-client-vpc"
  }
}

output "deployment_notice" {
  description = "Deployment notice and summary"
  value       = <<-EOT
    ╔═══════════════════════════════════════════════════════════════════╗
    ║  PHASE 1: FOUNDATION LAYER - PER-CLIENT VPC ARCHITECTURE          ║
    ╚═══════════════════════════════════════════════════════════════════╝
    
    SUCCESSFULLY DEPLOYED:
    - Dedicated client VPCs
    - Centralized Egress VPC with ${length(module.egress_vpc.nat_gateway_ids)} NAT Gateway(s)
    - Dynamic multi-AZ support using active region discovery


    NEXT PHASE: Layer 01.5 - Transit Gateway
    - Deploy Transit Gateway for centralized routing
    - Attach all VPCs (clients + egress) to Transit Gateway
    - Configure routing: Clients → TGW → Egress VPC → NAT → Internet
    
    
    COST ESTIMATE:
    - Egress VPC: $90/month (2 NAT Gateways for HA)
    - Transit Gateway: $36/month (in Layer 01.5)
    - Per-client VPC: ~$10/month (VPC endpoints only)
  EOT
}

