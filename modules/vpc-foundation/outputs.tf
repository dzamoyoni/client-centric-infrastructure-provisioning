# Outputs for VPC Foundation Module

# VPC Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Public Subnet Information
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

# Platform Subnet Information
output "platform_subnet_ids" {
  description = "List of platform subnet IDs"
  value       = aws_subnet.platform[*].id
}

output "platform_subnet_arns" {
  description = "List of platform subnet ARNs"
  value       = aws_subnet.platform[*].arn
}

output "platform_subnet_cidr_blocks" {
  description = "List of platform subnet CIDR blocks"
  value       = aws_subnet.platform[*].cidr_block
}

# NAT Gateway Information
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = aws_eip.nat[*].public_ip
}

# Internet Gateway Information
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# Route Table Information
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "platform_route_table_ids" {
  description = "List of platform route table IDs"
  value       = aws_route_table.platform[*].id
}

# VPC Endpoints
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

# Security Groups
output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.vpc_endpoints.id
}

# Flow Logs
output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = aws_flow_log.vpc.id
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow_log.name
}

# Availability Zones
output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}

# Summary Information
output "foundation_summary" {
  description = "Summary of foundation infrastructure created"
  value = {
    vpc_id                = aws_vpc.main.id
    vpc_cidr              = aws_vpc.main.cidr_block
    availability_zones    = var.availability_zones
    public_subnets        = length(aws_subnet.public)
    platform_subnets      = length(aws_subnet.platform)
    nat_gateways          = length(aws_nat_gateway.main)
    internet_gateway      = aws_internet_gateway.main.id
    vpc_endpoints_enabled = var.enable_vpc_endpoints
    vpc_flow_logs_enabled = var.enable_vpc_flow_logs
  }
}
