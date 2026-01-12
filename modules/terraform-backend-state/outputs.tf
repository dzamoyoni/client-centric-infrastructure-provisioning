# ============================================================================
# Terraform Backend State Module Outputs - Enterprise Standards
# ============================================================================

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "backend_bucket_name" {
  description = "The name of the S3 bucket used for Terraform state storage"
  value       = module.terraform_state_bucket.bucket_id
}

output "backend_bucket_arn" {
  description = "The ARN of the S3 bucket used for Terraform state storage"
  value       = module.terraform_state_bucket.bucket_arn
}

output "backend_bucket_region" {
  description = "The AWS region of the S3 bucket"
  value       = module.terraform_state_bucket.bucket_region
}

output "backend_bucket_domain_name" {
  description = "The bucket domain name"
  value       = module.terraform_state_bucket.bucket_domain_name
}

# ============================================================================
# DynamoDB Table Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

# ============================================================================
# Backend Configuration Outputs
# ============================================================================

output "backend_config" {
  description = "Backend configuration for use in other modules"
  value = {
    bucket         = module.terraform_state_bucket.bucket_id
    region         = var.region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt        = true
  }
}

# ============================================================================
# IAM Policy Outputs
# ============================================================================

output "access_policy_json" {
  description = "IAM policy JSON for accessing the backend resources"
  value       = data.aws_iam_policy_document.backend_access.json
}

output "access_policy_arn" {
  description = "ARN of the IAM policy for backend access (if created)"
  value       = null # This would need to be created as a resource
}

# ============================================================================
# SSM Parameter Outputs
# ============================================================================

output "ssm_parameters" {
  description = "SSM parameters created for backend configuration"
  value = {
    bucket_parameter_name = aws_ssm_parameter.backend_bucket.name
    table_parameter_name  = aws_ssm_parameter.backend_dynamodb_table.name
    region_parameter_name = aws_ssm_parameter.backend_region.name
  }
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for backend monitoring"
  value = var.enable_backend_monitoring ? {
    dynamodb_throttles_alarm     = try(aws_cloudwatch_metric_alarm.dynamodb_throttles[0].arn, null)
    s3_unauthorized_access_alarm = try(aws_cloudwatch_metric_alarm.s3_unauthorized_access[0].arn, null)
  } : null
}

# ============================================================================
# Backend Configuration Files Outputs
# ============================================================================

output "backend_config_files" {
  description = "Generated backend configuration files"
  value = var.generate_backend_configs ? {
    for layer_name, config in local.backend_layers :
    layer_name => {
      file_path = "${var.backend_config_output_path}/${var.environment}/${var.region}/${config.layer_name}.hcl"
      key_path  = config.key_path
    }
  } : {}
}

# ============================================================================
# Module Information Outputs
# ============================================================================

output "module_version" {
  description = "Version of this terraform backend state module"
  value       = "1.0.0"
}

output "deployment_timestamp" {
  description = "Timestamp when this backend was deployed"
  value       = timestamp()
}

# ============================================================================
# Compliance and Status Outputs  
# ============================================================================

output "compliance_status" {
  description = "Compliance status of the backend infrastructure"
  value = {
    s3_versioning_enabled            = module.terraform_state_bucket.versioning_enabled
    s3_encryption_enabled            = true
    dynamodb_encryption_enabled      = true
    point_in_time_recovery_enabled   = var.enable_dynamodb_point_in_time_recovery
    cross_region_replication_enabled = var.enable_cross_region_replication
    monitoring_enabled               = var.enable_backend_monitoring
  }
}

output "cost_optimization" {
  description = "Cost optimization features enabled"
  value = {
    intelligent_tiering = false # Not recommended for state files
    lifecycle_policies  = module.terraform_state_bucket.lifecycle_enabled
    on_demand_billing   = var.dynamodb_billing_mode == "ON_DEMAND"
  }
}