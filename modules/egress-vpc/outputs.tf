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

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.egress.id
}

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

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

output "spoke_return_route_ids" {
  description = "Map of return route IDs created in the public route table pointing back to Transit Gateway"
  value       = { for k, v in aws_route.public_to_spoke_tgw : k => v.id }
}

output "spoke_vpcs_cidrs" {
  description = "List of CIDR blocks configured for Spoke return traffic via TGW"
  value       = var.spoke_vpcs_cidrs
}