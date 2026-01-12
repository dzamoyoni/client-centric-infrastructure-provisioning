# ============================================================================
# Terraform Backend State Management Module - Enterprise Standards
# ============================================================================
# This module creates the infrastructure required for Terraform remote state:
# - S3 bucket for state storage with versioning and encryption
# - DynamoDB table for state locking
# - Follows your existing backend naming conventions
# - Integrates with your S3 bucket management module
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# Local Variables - Enterprise Backend Standards
# ============================================================================

locals {
  # Follow your existing naming convention: cptwn-terraform-state-ezra
  bucket_name = var.custom_bucket_name != "" ? var.custom_bucket_name : "${var.project_name}-terraform-state-${var.environment}"

  # Follow your existing DynamoDB naming convention: terraform-locks-af-south
  dynamodb_table_name = var.custom_dynamodb_name != "" ? var.custom_dynamodb_name : "terraform-locks-${var.region_short_name}"

  # Standard tags for backend resources
  backend_tags = merge(var.common_tags, {
    Project        = var.project_name
    Environment    = var.environment
    Region         = var.region
    Purpose        = "Terraform-Backend-State"
    ManagedBy      = "Terraform"
    CriticalInfra  = "true"
    BackupRequired = "true"
    SecurityLevel  = "Critical"
    Layer          = "Backend"
    Architecture   = "Client-Centric"
  })

  # Backend configuration files to generate
  backend_layers = var.generate_backend_configs ? {
    "01-foundation" = {
      layer_name = "foundation"
      key_path   = "providers/aws/regions/${var.region}/layers/01-foundation/${var.environment}/terraform.tfstate"
    }
    "02-platform" = {
      layer_name = "platform"
      key_path   = "regions/${var.region}/layers/02-platform/${var.environment}/terraform.tfstate"
    }
    "03-databases" = {
      layer_name = "databases"
      key_path   = "regions/${var.region}/layers/03-databases/${var.environment}/terraform.tfstate"
    }
    "03.5-observability" = {
      layer_name = "observability"
      key_path   = "regions/${var.region}/layers/03.5-observability/${var.environment}/terraform.tfstate"
    }
    "06-shared-services" = {
      layer_name = "shared-services"
      key_path   = "regions/${var.region}/layers/06-shared-services/${var.environment}/terraform.tfstate"
    }
  } : {}
}

# ============================================================================
# S3 Bucket for Terraform State - Using Your S3 Management Module
# ============================================================================

module "terraform_state_bucket" {
  source = "../s3-bucket-management"

  # Core configuration
  project_name       = var.project_name
  environment        = var.environment
  region             = var.region
  bucket_purpose     = "backend-state"
  custom_bucket_name = local.bucket_name

  # Security configuration - Critical for state files
  enable_versioning = var.enable_versioning
  prevent_destroy   = true           # Always prevent destruction
  kms_key_id        = var.kms_key_id # Optional KMS encryption

  # Enterprise Security Features - Enhanced for critical infrastructure
  enable_mfa_delete     = var.enable_mfa_delete
  versioning_mfa_delete = var.enable_mfa_delete
  object_ownership      = var.object_ownership

  # Access Logging - Critical for state file access tracking
  enable_access_logging = var.enable_access_logging

  # Advanced Monitoring - Essential for state management
  enable_cloudwatch_metrics      = var.enable_cloudwatch_metrics
  enable_analytics_configuration = var.enable_cloudwatch_metrics
  enable_inventory_configuration = var.enable_cloudwatch_metrics

  # Lifecycle policy - Optimized for state files
  enable_lifecycle_policy = true
  # Note: The S3 module automatically applies backend-state optimized policies:
  # - Never expire state files (expiration_days = 0)
  # - Keep 90 days of state versions for recovery
  # - No Glacier transitions (state files need immediate access)

  # Cross-region replication for disaster recovery
  enable_cross_region_replication    = var.enable_cross_region_replication
  replication_destination_bucket_arn = var.replication_destination_bucket_arn
  replication_storage_class          = "STANDARD" # State files need fast access
  replication_kms_key_id             = var.replication_kms_key_id

  # Monitoring and notifications
  enable_bucket_notifications = var.enable_state_monitoring
  enable_eventbridge          = var.enable_eventbridge || var.enable_state_monitoring
  notification_topics         = var.state_notification_topics

  # Cost optimization
  enable_cost_metrics        = true
  enable_intelligent_tiering = false # State files don't benefit from tiering

  # CPTWN standard tags
  common_tags = local.backend_tags
}

# ============================================================================
# DynamoDB Table for State Locking - Enterprise Standards
# ============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.dynamodb_table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "LockID"

  # Provisioned throughput (only used when billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-time recovery for critical infrastructure
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.dynamodb_kms_key_arn != "" ? var.dynamodb_kms_key_arn : null
  }

  # Table class optimization
  table_class = var.dynamodb_table_class

  # CPTWN standard tags
  tags = merge(local.backend_tags, {
    Name    = local.dynamodb_table_name
    Purpose = "Terraform State Locking"
  })

  # Prevent accidental deletion - Note: For dynamic control, manage this via Terraform workspace or variable
  # lifecycle {
  #   prevent_destroy = true  # Enable this manually for production
  # }
}

# ============================================================================
# Backend Configuration Files Generation (Optional)
# ============================================================================

# Generate backend configuration files following your structure
resource "local_file" "backend_configs" {
  for_each = local.backend_layers

  filename = "${var.backend_config_output_path}/${var.environment}/${var.region}/${each.value.layer_name}.hcl"

  content = templatefile("${path.module}/templates/backend-config.hcl.tpl", {
    bucket_name    = module.terraform_state_bucket.bucket_id
    key_path       = each.value.key_path
    region         = var.region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
  })

  # Ensure parent directories exist
  depends_on = [module.terraform_state_bucket, aws_dynamodb_table.terraform_locks]
}

# ============================================================================
# SSM Parameters for Backend Configuration (Integration with existing modules)
# ============================================================================

# Store backend configuration in SSM for other modules to reference
resource "aws_ssm_parameter" "backend_bucket" {
  name        = "/${var.project_name}/${var.environment}/backend/s3-bucket"
  type        = "String"
  value       = module.terraform_state_bucket.bucket_id
  description = "S3 bucket name for Terraform state storage"

  tags = local.backend_tags
}

resource "aws_ssm_parameter" "backend_dynamodb_table" {
  name        = "/${var.project_name}/${var.environment}/backend/dynamodb-table"
  type        = "String"
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB table name for Terraform state locking"

  tags = local.backend_tags
}

resource "aws_ssm_parameter" "backend_region" {
  name        = "/${var.project_name}/${var.environment}/backend/region"
  type        = "String"
  value       = var.region
  description = "AWS region for Terraform backend"

  tags = local.backend_tags
}

# ============================================================================
# CloudWatch Alarms for Backend Monitoring
# ============================================================================

# Monitor DynamoDB throttles
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_backend_monitoring ? 1 : 0

  alarm_name          = "${local.dynamodb_table_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttles for Terraform state locking"
  alarm_actions       = var.alarm_sns_topic_arns

  dimensions = {
    TableName = aws_dynamodb_table.terraform_locks.name
  }

  tags = local.backend_tags
}

# Monitor S3 bucket for unauthorized access
resource "aws_cloudwatch_metric_alarm" "s3_unauthorized_access" {
  count = var.enable_backend_monitoring ? 1 : 0

  alarm_name          = "${module.terraform_state_bucket.bucket_id}-unauthorized-access"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors unauthorized access attempts to Terraform state bucket"
  alarm_actions       = var.alarm_sns_topic_arns

  dimensions = {
    BucketName = module.terraform_state_bucket.bucket_id
  }

  tags = local.backend_tags
}

# ============================================================================
# Backup Strategy for State Files
# ============================================================================

# EventBridge rule to trigger state file backups
resource "aws_cloudwatch_event_rule" "state_file_backup" {
  count = var.enable_automated_backup ? 1 : 0

  name        = "${var.project_name}-${var.region}-state-backup"
  description = "Trigger backup of Terraform state files"

  schedule_expression = var.backup_schedule_expression

  tags = local.backend_tags
}

# ============================================================================
# IAM Policy for Backend Access (Reference for users)
# ============================================================================

# Create an IAM policy document that can be attached to users/roles
data "aws_iam_policy_document" "backend_access" {
  # S3 bucket permissions
  statement {
    sid    = "TerraformStateS3Access"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation"
    ]

    resources = [module.terraform_state_bucket.bucket_arn]
  }

  statement {
    sid    = "TerraformStateObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion"
    ]

    resources = ["${module.terraform_state_bucket.bucket_arn}/*"]
  }

  # DynamoDB permissions
  statement {
    sid    = "TerraformStateLocking"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [aws_dynamodb_table.terraform_locks.arn]
  }

  # KMS permissions (if using KMS encryption)
  dynamic "statement" {
    for_each = var.kms_key_id != "" ? [1] : []
    content {
      sid    = "TerraformStateKMSAccess"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]

      resources = [var.kms_key_id]
    }
  }
}

# Output the IAM policy for reference
resource "aws_iam_policy" "backend_access_policy" {
  count = var.create_access_policy ? 1 : 0

  name        = "${var.project_name}-${var.region}-terraform-backend-access"
  description = "Policy for accessing Terraform backend state and locking"
  policy      = data.aws_iam_policy_document.backend_access.json

  tags = local.backend_tags
}