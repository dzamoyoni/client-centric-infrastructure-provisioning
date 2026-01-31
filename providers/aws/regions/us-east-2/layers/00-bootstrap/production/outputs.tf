# ============================================================================
# Layer 00: Bootstrap Outputs
# ============================================================================
# These outputs are consumed by:
#   - Layer 06-Observability (via terraform_remote_state data source)
#   - Other layers that need state backend configuration
# ============================================================================

# ============================================================================
# Terraform State Infrastructure
# ============================================================================

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state storage"
  value = {
    id                  = module.terraform_state_bucket.bucket_id
    arn                 = module.terraform_state_bucket.bucket_arn
    region              = module.terraform_state_bucket.bucket_region
    domain_name         = module.terraform_state_bucket.bucket_domain_name
    versioning_enabled  = module.terraform_state_bucket.versioning_enabled
  }
}

output "terraform_locks_table" {
  description = "DynamoDB table for Terraform state locking"
  value = {
    name = aws_dynamodb_table.terraform_locks.name
    arn  = aws_dynamodb_table.terraform_locks.arn
  }
}

output "terraform_state_kms_key" {
  description = "KMS key for Terraform state encryption"
  value = {
    id     = aws_kms_key.terraform_state.id
    arn    = aws_kms_key.terraform_state.arn
    alias  = aws_kms_alias.terraform_state.name
  }
}

# ============================================================================
# Backend Configuration for Other Layers
# ============================================================================

output "backend_config" {
  description = "Backend configuration for layers 01-06 to use"
  value = {
    bucket         = module.terraform_state_bucket.bucket_id
    region         = var.region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt        = true
    kms_key_id     = aws_kms_key.terraform_state.id
  }
}

# ============================================================================
# Per-Client Observability Buckets
# ============================================================================

output "client_logs_buckets" {
  description = "Logs S3 buckets per client (for Fluent Bit, Loki)"
  value = {
    for client_name, _ in local.enabled_clients :
    client_name => {
      bucket_name = module.observability_buckets["${client_name}-logs"].bucket_id
      bucket_arn  = module.observability_buckets["${client_name}-logs"].bucket_arn
      region      = var.region
      
      # Expected directory structure
      structure = {
        infrastructure = "s3://${module.observability_buckets["${client_name}-logs"].bucket_id}/infrastructure/"
        application    = "s3://${module.observability_buckets["${client_name}-logs"].bucket_id}/application/"
        audit          = "s3://${module.observability_buckets["${client_name}-logs"].bucket_id}/audit/"
      }
    }
  }
}

output "client_metrics_buckets" {
  description = "Metrics S3 buckets per client (for Prometheus)"
  value = {
    for client_name, _ in local.enabled_clients :
    client_name => {
      bucket_name = module.observability_buckets["${client_name}-metrics"].bucket_id
      bucket_arn  = module.observability_buckets["${client_name}-metrics"].bucket_arn
      region      = var.region
      
      # Expected directory structure
      structure = {
        prometheus = "s3://${module.observability_buckets["${client_name}-metrics"].bucket_id}/prometheus/"
        database   = "s3://${module.observability_buckets["${client_name}-metrics"].bucket_id}/database/"
        cloudwatch = "s3://${module.observability_buckets["${client_name}-metrics"].bucket_id}/cloudwatch/"
      }
    }
  }
}

output "client_traces_buckets" {
  description = "Traces S3 buckets per client (for Tempo, Jaeger)"
  value = {
    for client_name, _ in local.enabled_clients :
    client_name => {
      bucket_name = module.observability_buckets["${client_name}-traces"].bucket_id
      bucket_arn  = module.observability_buckets["${client_name}-traces"].bucket_arn
      region      = var.region
      
      # Expected directory structure
      structure = {
        tempo         = "s3://${module.observability_buckets["${client_name}-traces"].bucket_id}/tempo/"
        jaeger        = "s3://${module.observability_buckets["${client_name}-traces"].bucket_id}/jaeger/"
        opentelemetry = "s3://${module.observability_buckets["${client_name}-traces"].bucket_id}/opentelemetry/"
      }
    }
  }
}

# ============================================================================
# IAM Roles for Observability Services
# ============================================================================

output "iam_roles" {
  description = "IAM roles for observability services"
  value = {
    prometheus = {
      role_name        = aws_iam_role.prometheus_s3_writer.name
      role_arn         = aws_iam_role.prometheus_s3_writer.arn
      instance_profile = aws_iam_instance_profile.prometheus.name
    }
    fluent_bit = {
      role_name        = aws_iam_role.fluent_bit_s3_writer.name
      role_arn         = aws_iam_role.fluent_bit_s3_writer.arn
      instance_profile = aws_iam_instance_profile.fluent_bit.name
    }
    tempo = {
      role_name        = aws_iam_role.tempo_s3_writer.name
      role_arn         = aws_iam_role.tempo_s3_writer.arn
      instance_profile = aws_iam_instance_profile.tempo.name
    }
  }
}

# ============================================================================
# Summary Information
# ============================================================================

output "summary" {
  description = "Summary of bootstrap infrastructure"
  value = {
    state_bucket_name       = module.terraform_state_bucket.bucket_id
    locks_table_name        = aws_dynamodb_table.terraform_locks.name
    total_clients           = length(local.enabled_clients)
    total_buckets_created   = length(local.enabled_clients) * 3 + 1  # 3 per client + 1 state bucket
    logs_retention          = "${var.logs_retention_days} days"
    metrics_retention       = "${var.metrics_retention_days} days"
    traces_retention        = "${var.traces_retention_days} days"
    region                  = var.region
    environment             = var.environment
  }
}

# ============================================================================
# Outputs for Documentation/README
# ============================================================================

output "enabled_clients" {
  description = "List of enabled clients with observability buckets"
  value       = keys(local.enabled_clients)
}

output "bucket_naming_pattern" {
  description = "Bucket naming pattern used"
  value = {
    logs    = "{client-name}-logs-{region}-{environment}"
    metrics = "{client-name}-metrics-{region}-{environment}"
    traces  = "{client-name}-traces-{region}-{environment}"
    state   = "terraform-state-{region}-{environment}"
  }
}
