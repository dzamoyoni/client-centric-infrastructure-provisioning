# ============================================================================
# S3 Module Outputs
# ============================================================================

output "bucket_id" {
  description = "The name of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "The AWS region this bucket resides in"
  value       = aws_s3_bucket.this.region
}

output "versioning_enabled" {
  description = "Whether versioning is enabled for this bucket"
  value       = var.versioning_enabled
}

output "encryption_type" {
  description = "The type of encryption used on this bucket"
  value       = var.encryption.type
}

output "intelligent_tiering_enabled" {
  description = "Whether Intelligent-Tiering is enabled for cost optimization"
  value       = var.intelligent_tiering.enabled
}
