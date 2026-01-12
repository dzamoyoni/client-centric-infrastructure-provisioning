# ============================================================================
# Foundation Layer Outputs - Per-Client VPC Architecture
# ============================================================================
# Each client has a dedicated VPC with complete network isolation
# Other layers access client-specific resources via: 
#   data.terraform_remote_state.foundation.outputs.client_vpcs["client-name"]
# ============================================================================

# Availability Zones
output "availability_zones" {
  description = "Availability zones used across all client VPCs"
  value       = local.availability_zones
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
    - Dual NAT gateways per client (High Availability)
    - VPC endpoints for cost optimization (S3, ECR)
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
    
    ➡️  NEXT PHASE: Layer 02 - Platform (EKS)
    - Access VPCs via: outputs.client_vpcs["client-name"].vpc_id
    - Each client gets dedicated EKS cluster in their VPC
    - Complete isolation between client workloads
    
    COST ESTIMATE: ~$89/month per client (2 NAT Gateways + VPC endpoints)
  EOT
}
