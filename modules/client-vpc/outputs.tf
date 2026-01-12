# ============================================================================
# Client VPC Module Outputs
# ============================================================================

# ============================================================================
# VPC Information
# ============================================================================

output "vpc_id" {
  description = "ID of the client VPC"
  value       = aws_vpc.client.id
}

output "vpc_arn" {
  description = "ARN of the client VPC"
  value       = aws_vpc.client.arn
}

output "vpc_cidr_block" {
  description = "CIDR block of the client VPC"
  value       = aws_vpc.client.cidr_block
}

# ============================================================================
# Public Subnet Information
# ============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of public subnet ARNs"
  value       = aws_subnet.public[*].arn
}

output "public_subnet_cidr_blocks" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

# ============================================================================
# EKS Subnet Information
# ============================================================================

output "eks_subnet_ids" {
  description = "List of EKS subnet IDs"
  value       = aws_subnet.eks[*].id
}

output "eks_subnet_arns" {
  description = "List of EKS subnet ARNs"
  value       = aws_subnet.eks[*].arn
}

output "eks_subnet_cidr_blocks" {
  description = "List of EKS subnet CIDR blocks"
  value       = aws_subnet.eks[*].cidr_block
}

# ============================================================================
# Database Subnet Information
# ============================================================================

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = aws_subnet.database[*].id
}

output "database_subnet_arns" {
  description = "List of database subnet ARNs"
  value       = aws_subnet.database[*].arn
}

output "database_subnet_cidr_blocks" {
  description = "List of database subnet CIDR blocks"
  value       = aws_subnet.database[*].cidr_block
}

# ============================================================================
# Compute Subnet Information
# ============================================================================

output "compute_subnet_ids" {
  description = "List of compute subnet IDs"
  value       = aws_subnet.compute[*].id
}

output "compute_subnet_arns" {
  description = "List of compute subnet ARNs"
  value       = aws_subnet.compute[*].arn
}

output "compute_subnet_cidr_blocks" {
  description = "List of compute subnet CIDR blocks"
  value       = aws_subnet.compute[*].cidr_block
}

# ============================================================================
# Security Group Information
# ============================================================================

output "eks_security_group_id" {
  description = "ID of the EKS security group"
  value       = aws_security_group.eks.id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "compute_security_group_id" {
  description = "ID of the compute security group"
  value       = aws_security_group.compute.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.vpc_endpoints.id
}

# ============================================================================
# NAT Gateway Information
# ============================================================================

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.client[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = aws_eip.nat[*].public_ip
}

# ============================================================================
# Internet Gateway Information
# ============================================================================

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.client.id
}

# ============================================================================
# Route Table Information
# ============================================================================

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

# ============================================================================
# VPC Endpoints
# ============================================================================

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "ecr_dkr_vpc_endpoint_id" {
  description = "ID of the ECR Docker VPC endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "ecr_api_vpc_endpoint_id" {
  description = "ID of the ECR API VPC endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

# ============================================================================
# Flow Logs
# ============================================================================

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = var.enable_flow_logs ? aws_flow_log.vpc[0].id : null
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.vpc_flow_log[0].name : null
}

# ============================================================================
# Availability Zones
# ============================================================================

output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}

# ============================================================================
# Summary Information
# ============================================================================

output "vpc_summary" {
  description = "Summary of VPC infrastructure created"
  value = {
    client_name           = var.client_name
    vpc_id                = aws_vpc.client.id
    vpc_cidr              = aws_vpc.client.cidr_block
    environment           = var.environment
    region                = var.region
    availability_zones    = var.availability_zones
    public_subnets        = length(aws_subnet.public)
    eks_subnets           = length(aws_subnet.eks)
    database_subnets      = length(aws_subnet.database)
    compute_subnets       = length(aws_subnet.compute)
    nat_gateways          = length(aws_nat_gateway.client)
    security_groups       = 4 # EKS, Database, Compute, VPC Endpoints
    vpc_flow_logs_enabled = var.enable_flow_logs
  }
}
