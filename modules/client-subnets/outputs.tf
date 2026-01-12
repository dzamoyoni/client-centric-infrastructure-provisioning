# Outputs for Client Subnet Isolation Module

# Compute Subnet Information
output "compute_subnet_ids" {
  description = "List of compute subnet IDs for this client"
  value       = aws_subnet.compute[*].id
}

output "compute_subnet_arns" {
  description = "List of compute subnet ARNs for this client"
  value       = aws_subnet.compute[*].arn
}

output "compute_subnet_cidr_blocks" {
  description = "List of compute subnet CIDR blocks for this client"
  value       = aws_subnet.compute[*].cidr_block
}

# Database Subnet Information
output "database_subnet_ids" {
  description = "List of database subnet IDs for this client"
  value       = aws_subnet.database[*].id
}

output "database_subnet_arns" {
  description = "List of database subnet ARNs for this client"
  value       = aws_subnet.database[*].arn
}

output "database_subnet_cidr_blocks" {
  description = "List of database subnet CIDR blocks for this client"
  value       = aws_subnet.database[*].cidr_block
}

# EKS Subnet Information
output "eks_subnet_ids" {
  description = "List of EKS subnet IDs for this client"
  value       = aws_subnet.eks[*].id
}

output "eks_subnet_arns" {
  description = "List of EKS subnet ARNs for this client"
  value       = aws_subnet.eks[*].arn
}

output "eks_subnet_cidr_blocks" {
  description = "List of EKS subnet CIDR blocks for this client"
  value       = aws_subnet.eks[*].cidr_block
}

# Security Group Information
output "compute_security_group_id" {
  description = "ID of the compute security group for this client"
  value       = var.enabled ? aws_security_group.compute[0].id : null
}

output "database_security_group_id" {
  description = "ID of the database security group for this client"
  value       = var.enabled ? aws_security_group.database[0].id : null
}

output "eks_security_group_id" {
  description = "ID of the EKS security group for this client"
  value       = var.enabled ? aws_security_group.eks[0].id : null
}

# Route Table Information
output "route_table_ids" {
  description = "List of route table IDs for this client"
  value       = aws_route_table.client[*].id
}

# Network ACL Information
output "network_acl_id" {
  description = "ID of the network ACL for this client"
  value       = var.enabled ? aws_network_acl.client[0].id : null
}

# Client Summary
output "client_summary" {
  description = "Summary of client infrastructure created"
  value = var.enabled ? {
    client_name             = var.client_name
    client_cidr_block       = var.client_cidr_block
    availability_zones      = var.availability_zones
    compute_subnets         = length(aws_subnet.compute)
    database_subnets        = length(aws_subnet.database)
    eks_subnets             = length(aws_subnet.eks)
    total_subnets           = length(aws_subnet.compute) + length(aws_subnet.database) + length(aws_subnet.eks)
    security_groups_created = 3
    route_tables_created    = length(aws_route_table.client)
    network_acl_created     = true
    database_type           = "PostgreSQL on EC2"
  } : null
}
