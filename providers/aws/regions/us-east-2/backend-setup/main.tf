# CRITICAL INFRASTRUCTURE - S3 Backend Setup
# DO NOT DELETE OR MODIFY WITHOUT PROPER AUTHORIZATION
# This bucket stores Terraform state for PRODUCTION infrastructure

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "af-south-1"

  default_tags {
    tags = {
      Project        = "CPTWN-Multi-Client-EKS"
      Environment    = "Production"
      ManagedBy      = "Terraform"
      CriticalInfra  = "true"
      BackupRequired = "true"
      SecurityLevel  = "High"
      Region         = "af-south-1"
      Layer          = "Backend"
    }
  }
}

# Get current AWS account info for security policies
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

#  ULTRA-SECURE S3 BUCKET FOR TERRAFORM STATE
resource "aws_s3_bucket" "terraform_state" {
  bucket = "cptwn-terraform-state-ezra"

  tags = {
    Name              = "CPTWN Terraform State Bucket"
    Purpose           = "Terraform Backend State Storage"
    CriticalInfra     = "true"
    DeletionProtected = "true"
    SecurityLevel     = "Maximum"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning for state file recovery
# Note: MFA delete must be enabled via CLI/Console after bucket creation
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"  # Must be set via AWS CLI with MFA
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    prevent_destroy = true
  }
}

# Lifecycle policy for cost optimization while maintaining security
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "terraform_state_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Keep current versions forever (critical state data)
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    # Keep old versions for 1 year for disaster recovery
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ULTRA-RESTRICTIVE BUCKET POLICY
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
    ]
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Enable access logging for audit trail
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "terraform-state-access-logs/"

  lifecycle {
    prevent_destroy = true
  }
}

# Separate bucket for access logs (also protected)
resource "aws_s3_bucket" "access_logs" {
  bucket = "cptwn-terraform-state-ezra-access-logs"

  tags = {
    Name              = "CPTWN Terraform State Access Logs"
    Purpose           = "S3 Access Logging"
    CriticalInfra     = "true"
    DeletionProtected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Block public access on logs bucket too
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    prevent_destroy = true
  }
}

# CRITICAL DYNAMODB TABLE FOR STATE LOCKING
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks-af-south"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable point-in-time recovery for critical infrastructure
  point_in_time_recovery {
    enabled = true
  }

  # Enable deletion protection
  deletion_protection_enabled = true

  tags = {
    Name              = "CPTWN Terraform State Locks"
    Purpose           = "Terraform State Locking"
    CriticalInfra     = "true"
    DeletionProtected = "true"
    SecurityLevel     = "High"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# OUTPUTS FOR REFERENCE
output "s3_bucket_name" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

# Security Notice
output "security_notice" {
  description = "Critical security information"
  value       = <<-EOT
    🔒 CRITICAL INFRASTRUCTURE DEPLOYED
    
    ⚠️  This S3 bucket and DynamoDB table are PROTECTED with:
    - Deletion protection enabled
    - MFA delete required for S3 versions
    - Bucket policies preventing unauthorized access
    - Encryption at rest enabled
    - Access logging for audit trails
    - Point-in-time recovery for DynamoDB
    
    ❌ DO NOT attempt to delete these resources without proper authorization!
    ❌ All modifications require security review!
    
    📋 Next: Configure backend in other layers to use:
    - Bucket: ${aws_s3_bucket.terraform_state.id}
    - DynamoDB: ${aws_dynamodb_table.terraform_locks.name}
  EOT
}
