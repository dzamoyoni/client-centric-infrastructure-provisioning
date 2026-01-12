# ============================================================================
# Unified Foundation Layer Module Outputs
# ============================================================================
# Provides identical outputs regardless of import/create mode for consistency
# ============================================================================

# ============================================================================
# Mode Information
# ============================================================================

output "foundation_mode" {
  description = "Foundation layer operational mode (IMPORT or CREATE)"
  value       = local.mode_name
}

output "is_import_mode" {
  description = "Whether foundation layer is in import mode"
  value       = local.is_import_mode
}

# ============================================================================
# VPC Outputs
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = local.is_import_mode ? data.aws_vpc.existing[0].arn : module.vpc[0].vpc_arn
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = local.vpc_cidr_block
}

# ============================================================================
# Subnet Outputs
# ============================================================================

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = local.private_subnet_ids
}

output "private_subnets_cidr_blocks" {
  description = "List of CIDR blocks of the private subnets"
  value       = local.private_subnet_cidrs
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = local.public_subnet_ids
}

output "public_subnets_cidr_blocks" {
  description = "List of CIDR blocks of the public subnets"
  value       = local.public_subnet_cidrs
}

# ============================================================================
# Gateway Outputs
# ============================================================================

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = local.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = local.nat_gateway_ids
}

# ============================================================================
# Security Group Outputs
# ============================================================================

output "eks_cluster_security_group_id" {
  description = "ID of the EKS cluster security group"
  value       = local.eks_cluster_sg_id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = local.database_sg_id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = local.alb_sg_id
}

# ============================================================================
# VPN Outputs
# ============================================================================

output "vpn_enabled" {
  description = "Whether VPN is enabled"
  value       = local.vpn_enabled
}

output "vpn_gateway_id" {
  description = "ID of the VPN Gateway"
  value       = local.vpn_gateway_id != "" ? local.vpn_gateway_id : null
}

# ============================================================================
# SSM Parameter Names (for reference by other layers)
# ============================================================================

output "ssm_parameter_names" {
  description = "Map of SSM parameter names for cross-layer reference"
  value = {
    vpc_id                        = aws_ssm_parameter.vpc_id.name
    vpc_cidr                      = aws_ssm_parameter.vpc_cidr.name
    private_subnets               = aws_ssm_parameter.private_subnets.name
    public_subnets                = aws_ssm_parameter.public_subnets.name
    private_subnet_cidrs          = aws_ssm_parameter.private_subnet_cidrs.name
    public_subnet_cidrs           = aws_ssm_parameter.public_subnet_cidrs.name
    internet_gateway_id           = length(aws_ssm_parameter.internet_gateway_id) > 0 ? aws_ssm_parameter.internet_gateway_id[0].name : null
    nat_gateway_ids               = length(aws_ssm_parameter.nat_gateway_ids) > 0 ? aws_ssm_parameter.nat_gateway_ids[0].name : null
    eks_cluster_security_group_id = length(aws_ssm_parameter.eks_cluster_sg_id) > 0 ? aws_ssm_parameter.eks_cluster_sg_id[0].name : null
    database_security_group_id    = length(aws_ssm_parameter.database_sg_id) > 0 ? aws_ssm_parameter.database_sg_id[0].name : null
    alb_security_group_id         = length(aws_ssm_parameter.alb_sg_id) > 0 ? aws_ssm_parameter.alb_sg_id[0].name : null
    vpn_enabled                   = aws_ssm_parameter.vpn_enabled.name
    vpn_gateway_id                = length(aws_ssm_parameter.vpn_gateway_id) > 0 ? aws_ssm_parameter.vpn_gateway_id[0].name : null
    deployed                      = aws_ssm_parameter.deployed.name
    version                       = aws_ssm_parameter.version.name
    mode                          = aws_ssm_parameter.mode.name
    region                        = aws_ssm_parameter.region.name
    availability_zones            = aws_ssm_parameter.availability_zones.name
  }
}

# ============================================================================
# Resource Summaries
# ============================================================================

output "network_summary" {
  description = "Summary of network configuration"
  value = {
    mode                 = local.mode_name
    vpc_id               = local.vpc_id
    vpc_cidr             = local.vpc_cidr_block
    availability_zones   = var.availability_zones
    private_subnet_count = length(local.private_subnet_ids)
    public_subnet_count  = length(local.public_subnet_ids)
    nat_gateway_count    = length(local.nat_gateway_ids)
    vpn_enabled          = local.vpn_enabled
    region               = var.aws_region
  }
}

output "security_summary" {
  description = "Summary of security groups"
  value = {
    mode              = local.mode_name
    eks_cluster_sg_id = local.eks_cluster_sg_id
    database_sg_id    = local.database_sg_id
    alb_sg_id         = local.alb_sg_id
    created_new_sgs   = var.create_security_groups
  }
}

output "deployment_summary" {
  description = "Summary of foundation layer deployment"
  value = {
    mode                   = local.mode_name
    environment            = var.environment
    region                 = var.aws_region
    foundation_deployed    = true
    vpc_protected          = local.is_import_mode
    ssm_parameters_created = true
    consistent_interface   = true
  }
}
