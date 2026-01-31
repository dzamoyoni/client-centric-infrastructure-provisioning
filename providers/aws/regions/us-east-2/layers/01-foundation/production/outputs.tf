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

# Availability Zones
output "availability_zones" {
  description = "Availability zones used across all client VPCs"
  value       = local.availability_zones
}

output "organization_name" {
  description = "Organization name for resource naming"
  value       = "Org Name"  # Organization name
}

# ============================================================================
# Per-Client VPC Infrastructure - Primary Output
# ============================================================================
# Access pattern: outputs.client_vpcs["client-name"].vpc_id
# Example: data.terraform_remote_state.foundation.outputs.client_vpcs["est-test-a"].vpc_id

output "client_vpcs" {
  description = "Complete VPC infrastructure per client - use this for cross-layer lookups"
  value = {
    for name, vpc_module in module.client_vpcs : name => {
      # VPC Details
      vpc_id         = vpc_module.vpc_id
      vpc_cidr       = vpc_module.vpc_cidr_block
      
      # Subnet IDs (for resource placement)
      public_subnet_ids   = vpc_module.public_subnet_ids
      eks_subnet_ids      = vpc_module.eks_subnet_ids
      database_subnet_ids = vpc_module.database_subnet_ids
      compute_subnet_ids  = vpc_module.compute_subnet_ids
      
      # Security Groups (for resource attachment)
      eks_security_group_id      = vpc_module.eks_security_group_id
      database_security_group_id = vpc_module.database_security_group_id
      compute_security_group_id  = vpc_module.compute_security_group_id
      
      # NAT Gateways (for reference)
      nat_gateway_ids        = vpc_module.nat_gateway_ids
      nat_gateway_public_ips = vpc_module.nat_gateway_public_ips
      
      # Route Tables (for VPN integration)
      private_route_table_ids = vpc_module.private_route_table_ids
      
      # VPC Endpoints
      s3_vpc_endpoint_id      = vpc_module.s3_vpc_endpoint_id
      ecr_dkr_vpc_endpoint_id = vpc_module.ecr_dkr_vpc_endpoint_id
      ecr_api_vpc_endpoint_id = vpc_module.ecr_api_vpc_endpoint_id
      
      # Client Metadata
      client_code = var.clients[name].client_code
      tier        = var.clients[name].tier
      metadata    = var.clients[name].metadata
    }
  }
}

# ============================================================================
# Egress VPC - Centralized NAT Gateway
# ============================================================================

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

output "egress_nat_gateway_ids" {
  description = "NAT Gateway IDs in Egress VPC"
  value       = module.egress_vpc.nat_gateway_ids
}

output "egress_nat_gateway_public_ips" {
  description = "Public IPs of NAT Gateways in Egress VPC (for whitelisting)"
  value       = module.egress_vpc.nat_gateway_public_ips
}

# ============================================================================
# Outputs for Layer 01.5 (Transit Gateway)
# ============================================================================

output "foundation_vpc_id" {
  description = "Foundation VPC ID (if deployed separately)"
  value       = null  # Not currently using foundation VPC, only client VPCs
}

output "foundation_vpc_cidr" {
  description = "Foundation VPC CIDR (if deployed)"
  value       = null
}

output "foundation_platform_subnet_ids" {
  description = "Foundation platform subnet IDs for TGW attachment"
  value       = []  # Empty for client-centric architecture
}

output "foundation_platform_route_table_ids" {
  description = "Foundation platform route table IDs for TGW routing"
  value       = []  # Empty for client-centric architecture
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
  description = "Map of client EKS subnet IDs (for Transit Gateway attachment)"
  value = {
    for name, vpc in module.client_vpcs : name => vpc.eks_subnet_ids
  }
}

output "client_private_route_table_ids" {
  description = "Map of client private route table IDs (for Transit Gateway routing)"
  value = {
    for name, vpc in module.client_vpcs : name => vpc.private_route_table_ids
  }
}

# ============================================================================
# Per-Client VPN Connections
# ============================================================================
# Only created for clients with vpn.enabled = true

output "client_vpn_connections" {
  description = "VPN connections per client (only for clients with VPN enabled)"
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
  description = "List of client names with VPN enabled (for Layer 01.5 routing exclusion)"
  value = [
    for name, config in var.clients : name
    if config.enabled && try(config.vpn.enabled, false)
  ]
}

# ============================================================================
# Foundation Summary
# ============================================================================

output "foundation_summary" {
  description = "Summary of per-client VPC infrastructure deployed"
  value = {
    region             = var.region
    environment        = var.environment
    availability_zones = local.availability_zones

    # Per-client VPC counts
    total_clients       = length(local.enabled_clients)
    provisioned_clients = keys(local.enabled_clients)
    
    # CIDR allocations per client
    client_vpcs = {
      for name, config in local.enabled_clients : name => {
        vpc_cidr    = config.network.vpc_cidr
        client_code = config.client_code
        tier        = config.tier
      }
    }
    
    # Per-client infrastructure counts
    per_client_resources = {
      for name, vpc_module in module.client_vpcs : name => {
        vpc_id            = vpc_module.vpc_id
        public_subnets    = length(vpc_module.public_subnet_ids)
        eks_subnets       = length(vpc_module.eks_subnet_ids)
        database_subnets  = length(vpc_module.database_subnet_ids)
        compute_subnets   = length(vpc_module.compute_subnet_ids)
        nat_gateways      = length(vpc_module.nat_gateway_ids)
        security_groups   = 4  # EKS, Database, Compute, VPC Endpoints
        vpn_enabled       = can(var.clients[name].vpn.enabled) ? var.clients[name].vpn.enabled : false
      }
    }

    # Security & Monitoring
    vpc_flow_logs_enabled = true
    vpc_endpoints_enabled = true
    architecture          = "per-client-vpc"
  }
}

# ============================================================================
# Deployment Notice
# ============================================================================

output "deployment_notice" {
  description = "Per-Client VPC Architecture deployment summary and next steps"
  value       = <<-EOT
    ╔═══════════════════════════════════════════════════════════════════╗
    ║  PHASE 1: FOUNDATION LAYER - PER-CLIENT VPC ARCHITECTURE         ║
    ╚═══════════════════════════════════════════════════════════════════╝
    
    SUCCESSFULLY DEPLOYED:
    - Per-client VPCs with complete network isolation
    - Centralized Egress VPC with ${length(module.egress_vpc.nat_gateway_ids)} NAT Gateway(s)
    - Transit Gateway-ready architecture (NAT disabled in client VPCs)
    - VPC endpoints for cost optimization (S3, ECR, DynamoDB)
    - VPC Flow Logs for security monitoring
    - Layered security groups per client
    ${length(module.client_vpn) > 0 ? "- Site-to-Site VPN connections\n" : ""}
    
    CLIENT VPC SUMMARY:
    - Total Clients: ${length(local.enabled_clients)}
    - Provisioned Clients: ${join(", ", keys(local.enabled_clients))}
    - Architecture: Dedicated VPC per client
    
    CIDR ALLOCATIONS:
    ${join("\n    ", [for name, config in local.enabled_clients : "  • ${name}: ${config.network.vpc_cidr}"])}
    
    CLIENT ONBOARDING:
    1. Add client to cidr-registry.yaml with unique CIDR
    2. Run: ./scripts/validate-cidr.sh
    3. Add client config to clients.auto.tfvars
    4. Apply: terraform plan && terraform apply
    
    ➡️  NEXT PHASE: Layer 01.5 - Transit Gateway
    - Deploy Transit Gateway for centralized routing
    - Attach all VPCs (clients + egress) to Transit Gateway
    - Configure routing: Clients → TGW → Egress VPC → NAT → Internet
    
    
    ➡️ COST ESTIMATE:
    - Egress VPC: $90/month (2 NAT Gateways for HA)
    - Transit Gateway: $36/month (in Layer 01.5)
    - Per-client VPC: ~$10/month (VPC endpoints only)
    - Total for 3 clients: ~$126/month vs $270/month (53% savings!)
  EOT
}
