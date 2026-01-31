# ============================================================================
# Terraform State Infrastructure
# ============================================================================
# Creates:
#   1. S3 bucket for Terraform state storage (all layers 01-06)
#   2. DynamoDB table for state locking
#   3. KMS key for state encryption
#
# All other layers (01-06) will use this S3 bucket for remote state
# ============================================================================

# ============================================================================
# KMS Key for Terraform State Encryption
# ============================================================================

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(
    module.tags.standard_tags,
    {
      Name        = "terraform-state-encryption-key"
      ResourceType = "KMS-Key"
      Purpose     = "Terraform-State-Encryption"
    }
  )
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state-${var.environment}"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ============================================================================
# S3 Bucket for Terraform State
# ============================================================================

module "terraform_state_bucket" {
  source = "../../../../../../../modules/s3"

  bucket_name = "terraform-state-${var.region}-${var.environment}"

  # Versioning REQUIRED for state recovery
  versioning_enabled = true

  # KMS encryption for sensitive state data
  encryption = {
    type       = "aws:kms"
    kms_key_id = aws_kms_key.terraform_state.id
  }

  # Lifecycle for noncurrent versions (keep old versions for audit)
  lifecycle_rules = {
    # Keep noncurrent versions in Standard-IA after 30 days
    noncurrent_version_transition_ia = 30

    # Move to Glacier after 90 days
    noncurrent_version_transition_glacier = 90

    # Delete noncurrent versions after 1 year (audit retention)
    noncurrent_version_expiration = 365

    # Cleanup incomplete uploads
    abort_incomplete_multipart_upload_days = 7

    # NEVER delete current version (state must persist indefinitely)
    # expiration = null (not set)
  }

  # Security: Block all public access
  block_public_access = true

  # Industrial tagging (sanitized for LocalStack)
  tags = merge(
    local.sanitized_standard_tags,
    {
      Name               = "terraform-state-bucket"
      ResourceType       = "Terraform-State"
      BackupRequired     = "true"
      DataClassification = "Confidential"
      Compliance         = "SOC2-ISO27001"
      LifecyclePolicy    = "Versioned-Keep-Current-Archive-Old"
      CriticalData       = "true"
    }
  )
}

# ============================================================================
# DynamoDB Table for State Locking
# ============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks-${var.region}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # Cost-effective for low usage
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-time recovery (industrial standard)
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "terraform-locks-table"
      ResourceType = "Terraform-Lock"
      Purpose      = "State-Locking"
    }
  )
}

# ============================================================================
# S3 Bucket Policy - Allow Terraform State Access
# ============================================================================

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = module.terraform_state_bucket.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforcedTLS"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          module.terraform_state_bucket.bucket_arn,
          "${module.terraform_state_bucket.bucket_arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "DenyUnencryptedObjectUploads"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "${module.terraform_state_bucket.bucket_arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}
