# ============================================================================
# S3 Infrastructure Provisioning Outputs
# ============================================================================

output "provisioning_summary" {
  description = "Summary of provisioned infrastructure"
  value = {
    project_name = "ohio-01"
    environment  = "production"
    region      = "us-east-2"
    timestamp   = timestamp()
  }
}

output "backend_infrastructure" {
  description = "Backend infrastructure details"
  value = {
    s3_bucket_name    = module.terraform_backend_state.backend_bucket_name
    s3_bucket_arn     = module.terraform_backend_state.backend_bucket_arn
    dynamodb_table    = module.terraform_backend_state.dynamodb_table_name
    region           = "us-east-2"
    iam_policy_arn   = module.terraform_backend_state.access_policy_arn
  }
}

output "observability_infrastructure" {
  description = "Observability infrastructure details"
  value = {
    logs_bucket_name       = module.logs_bucket.bucket_id
    logs_bucket_arn        = module.logs_bucket.bucket_arn
    traces_bucket_name     = module.traces_bucket.bucket_id
    traces_bucket_arn      = module.traces_bucket.bucket_arn
    metrics_bucket_name    = module.metrics_bucket.bucket_id
    metrics_bucket_arn     = module.metrics_bucket.bucket_arn
    audit_logs_bucket_name = module.audit_logs_bucket.bucket_id
    audit_logs_bucket_arn  = module.audit_logs_bucket.bucket_arn
  }
}
