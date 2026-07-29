# ============================================================================
# Egress VPC Module - Outputs
# ============================================================================

output "vpc_id" {
  description = "ID of the egress VPC"
  value       = aws_vpc.egress.id
}

output "vpc_cidr" {
  description = "CIDR block of the egress VPC"
  value       = aws_vpc.egress.cidr_block
}

output "vpc_arn" {
  description = "ARN of the egress VPC"
  value       = aws_vpc.egress.arn
}

# ============================================================================
# Internet Gateway
# ============================================================================

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.egress.id
}

# ============================================================================
# Subnets
# ============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (for Transit Gateway attachment)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

# ============================================================================
# NAT Gateways
# ============================================================================

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.egress[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_count" {
  description = "Number of NAT Gateways deployed"
  value       = length(aws_nat_gateway.egress)
}

# ============================================================================
# Route Tables
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
  description = "ID of the S3 VPC endpoint (if enabled)"
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "dynamodb_vpc_endpoint_id" {
  description = "ID of the DynamoDB VPC endpoint (if enabled)"
  value       = try(aws_vpc_endpoint.dynamodb[0].id, null)
}

# ============================================================================
# Security Groups
# ============================================================================

output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group (if enabled)"
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}

# ============================================================================
# Flow Logs
# ============================================================================

output "flow_log_id" {
  description = "ID of the VPC flow log (if enabled)"
  value       = try(aws_flow_log.egress[0].id, null)
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group for flow logs (if enabled)"
  value       = try(aws_cloudwatch_log_group.vpc_flow_log[0].name, null)
}

output "flow_log_role_arn" {
  description = "The ARN of the IAM role used for VPC Flow Logs."
  value       = local.flow_log_role_arn
}
# ============================================================================
# Cost Information
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD (excluding data transfer)"
  value = {
    nat_gateways  = length(aws_nat_gateway.egress) * 45
    tgw_attachment = 36
    total         = (length(aws_nat_gateway.egress) * 45) + 36
    note          = "Excludes data transfer charges. Add $0.045/GB for NAT processing and $0.02/GB for TGW data transfer."
  }
}
