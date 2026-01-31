# ============================================================================
# S3 Bucket Module
# ============================================================================
# Purpose: Reusable S3 bucket with security-first design and cost optimization
# Features:
#   - Security by default (block public access, encryption, SSL)
#   - Cost optimization (intelligent-tiering, lifecycle policies)
#   - Compliance (logging, versioning, object lock support)
#   - Flexible configuration
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ============================================================================
# S3 Bucket
# ============================================================================

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

# ============================================================================
# Block Public Access 
# ============================================================================

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# ============================================================================
# Versioning
# ============================================================================

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}

# ============================================================================
# Server-Side Encryption
# ============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption.type == "aws:kms" ? "aws:kms" : "AES256"
      kms_master_key_id = var.encryption.type == "aws:kms" ? var.encryption.kms_key_id : null
    }
    bucket_key_enabled = var.encryption.type == "aws:kms" ? true : false
  }
}

# ============================================================================
# Logging (Optional)
# ============================================================================

resource "aws_s3_bucket_logging" "this" {
  count = var.logging.enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging.target_bucket
  target_prefix = var.logging.target_prefix
}

# ============================================================================
# CORS Configuration (Optional)
# ============================================================================

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", [])
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", 3600)
    }
  }
}

# ============================================================================
# Bucket Policy (Optional)
# ============================================================================

resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy != null ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.bucket_policy
}

# ============================================================================
# Object Lock Configuration (Optional - for compliance)
# ============================================================================

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock.enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock.mode
      days = var.object_lock.days
    }
  }
}
