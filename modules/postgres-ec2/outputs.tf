# ============================================================================
# PostgreSQL on EC2 Module - Outputs
# ============================================================================

# ===================================================================================
# MASTER INSTANCE OUTPUTS
# ===================================================================================

output "master_instance_id" {
  description = "ID of the master PostgreSQL instance"
  value       = module.master_instance.id
}

output "master_instance_arn" {
  description = "ARN of the master PostgreSQL instance"
  value       = module.master_instance.arn
}

output "master_private_ip" {
  description = "Private IP address of the master PostgreSQL instance"
  value       = module.master_instance.private_ip
}

output "master_availability_zone" {
  description = "Availability Zone of the master PostgreSQL instance"
  value       = module.master_instance.availability_zone
}

output "master_endpoint" {
  description = "Connection endpoint for the master PostgreSQL database"
  value       = var.create_dns_records ? aws_route53_record.master[0].name : module.master_instance.private_ip
}

# ===================================================================================
# REPLICA INSTANCE OUTPUTS
# ===================================================================================

output "replica_instance_id" {
  description = "ID of the replica PostgreSQL instance"
  value       = var.enable_replica ? module.replica_instance[0].id : null
}

output "replica_instance_arn" {
  description = "ARN of the replica PostgreSQL instance"
  value       = var.enable_replica ? module.replica_instance[0].arn : null
}

output "replica_private_ip" {
  description = "Private IP address of the replica PostgreSQL instance"
  value       = var.enable_replica ? module.replica_instance[0].private_ip : null
}

output "replica_availability_zone" {
  description = "Availability Zone of the replica PostgreSQL instance"
  value       = var.enable_replica ? module.replica_instance[0].availability_zone : null
}

output "replica_endpoint" {
  description = "Connection endpoint for the replica PostgreSQL database"
  value       = var.enable_replica ? (var.create_dns_records ? aws_route53_record.replica[0].name : module.replica_instance[0].private_ip) : null
}

# ===================================================================================
# SECURITY GROUP OUTPUTS
# ===================================================================================

output "security_group_id" {
  description = "ID of the PostgreSQL security group"
  value       = aws_security_group.postgres.id
}

output "security_group_arn" {
  description = "ARN of the PostgreSQL security group"
  value       = aws_security_group.postgres.arn
}

# ===================================================================================
# DATABASE CONNECTION INFORMATION
# ===================================================================================

output "database_port" {
  description = "PostgreSQL database port"
  value       = var.postgres_port
}

output "database_name" {
  description = "Name of the PostgreSQL database"
  value       = var.database_name
}

output "database_user" {
  description = "PostgreSQL database username"
  value       = var.database_user
  sensitive   = true
}

# ===================================================================================
# STORAGE OUTPUTS
# ===================================================================================
# Note: Volume IDs are managed by the EC2 module and available via AWS Console

# ===================================================================================
# DNS OUTPUTS
# ===================================================================================

output "master_dns_name" {
  description = "DNS name for master database (if DNS records are created)"
  value       = var.create_dns_records ? aws_route53_record.master[0].name : null
}

output "replica_dns_name" {
  description = "DNS name for replica database (if DNS records are created)"
  value       = var.enable_replica && var.create_dns_records ? aws_route53_record.replica[0].name : null
}

# ===================================================================================
# SSM PARAMETER OUTPUTS
# ===================================================================================

output "ssm_master_endpoint_parameter" {
  description = "SSM parameter name for master database endpoint"
  value       = aws_ssm_parameter.master_endpoint.name
}

output "ssm_replica_endpoint_parameter" {
  description = "SSM parameter name for replica database endpoint"
  value       = var.enable_replica ? aws_ssm_parameter.replica_endpoint[0].name : null
}

output "ssm_database_port_parameter" {
  description = "SSM parameter name for database port"
  value       = aws_ssm_parameter.database_port.name
}

output "ssm_database_name_parameter" {
  description = "SSM parameter name for database name"
  value       = aws_ssm_parameter.database_name.name
}

# ===================================================================================
# HIGH AVAILABILITY STATUS
# ===================================================================================

output "high_availability_enabled" {
  description = "Whether high availability (replica) is enabled"
  value       = var.enable_replica
}

output "replication_status" {
  description = "Replication configuration status"
  value = {
    enabled    = var.enable_replica
    master_az  = module.master_instance.availability_zone
    replica_az = var.enable_replica ? module.replica_instance[0].availability_zone : null
    cross_az   = var.enable_replica ? (module.master_instance.availability_zone != module.replica_instance[0].availability_zone) : false
  }
}

# ===================================================================================
# CLIENT ISOLATION INFORMATION
# ===================================================================================

output "client_name" {
  description = "Client name for this database deployment"
  value       = var.client_name
}

output "environment" {
  description = "Environment for this database deployment"
  value       = var.environment
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Client      = var.client_name
    Environment = var.environment
    Service     = "database"
    Engine      = "postgresql"
    ManagedBy   = "terraform"
  }
}
