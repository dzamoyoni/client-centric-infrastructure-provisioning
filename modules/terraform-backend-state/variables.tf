# ============================================================================
# Terraform Backend State Module Variables - Enterprise Standards
# ============================================================================

# ============================================================================
# Core Configuration Variables
# ============================================================================

variable "project_name" {
  description = "Name of the project (e.g., myproject)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "region" {
  description = "AWS region for the backend resources"
  type        = string
}

variable "region_short_name" {
  description = "Short name for the region (e.g., af-south for af-south-1)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Custom Naming Variables
# ============================================================================

variable "custom_bucket_name" {
  description = "Custom S3 bucket name (follows your existing convention if empty)"
  type        = string
  default     = ""
}

variable "custom_dynamodb_name" {
  description = "Custom DynamoDB table name (follows your existing convention if empty)"
  type        = string
  default     = ""
}

# ============================================================================
# Security Configuration Variables
# ============================================================================

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (empty string for AES256)"
  type        = string
  default     = ""
}

variable "dynamodb_kms_key_arn" {
  description = "KMS key ARN for DynamoDB encryption"
  type        = string
  default     = ""
}

variable "prevent_destroy" {
  description = "Prevent destruction of backend resources"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete for versioned objects"
  type        = bool
  default     = false
}

variable "object_ownership" {
  description = "Object ownership setting for the bucket"
  type        = string
  default     = "BucketOwnerEnforced"
  validation {
    condition     = contains(["BucketOwnerPreferred", "ObjectWriter", "BucketOwnerEnforced"], var.object_ownership)
    error_message = "Object ownership must be BucketOwnerPreferred, ObjectWriter, or BucketOwnerEnforced."
  }
}

variable "enable_access_logging" {
  description = "Enable access logging for the S3 bucket"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_metrics" {
  description = "Enable CloudWatch metrics for the S3 bucket"
  type        = bool
  default     = false
}

variable "enable_eventbridge" {
  description = "Enable EventBridge notifications for the bucket"
  type        = bool
  default     = false
}

# ============================================================================
# DynamoDB Configuration Variables
# ============================================================================

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
}

variable "dynamodb_table_class" {
  description = "DynamoDB table class (STANDARD or STANDARD_INFREQUENT_ACCESS)"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.dynamodb_table_class)
    error_message = "DynamoDB table class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "enable_dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

# ============================================================================
# Cross-Region Replication Variables
# ============================================================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for the state bucket"
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "ARN of destination bucket for replication"
  type        = string
  default     = ""
}

variable "replication_kms_key_id" {
  description = "KMS key ID for replication encryption"
  type        = string
  default     = ""
}

# ============================================================================
# Monitoring and Alerting Variables
# ============================================================================

variable "enable_backend_monitoring" {
  description = "Enable CloudWatch monitoring for backend resources"
  type        = bool
  default     = true
}

variable "enable_state_monitoring" {
  description = "Enable S3 bucket notifications and monitoring for state files"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs for CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "state_notification_topics" {
  description = "SNS topics for state bucket notifications"
  type = list(object({
    arn           = string
    events        = list(string)
    filter_prefix = optional(string, "")
    filter_suffix = optional(string, "")
  }))
  default = []
}

# ============================================================================
# Backup Configuration Variables
# ============================================================================

variable "enable_automated_backup" {
  description = "Enable automated backup of state files"
  type        = bool
  default     = true
}

variable "backup_schedule_expression" {
  description = "Schedule expression for automated backups (cron or rate)"
  type        = string
  default     = "rate(24 hours)"
}

# ============================================================================
# Backend Configuration Generation Variables
# ============================================================================

variable "generate_backend_configs" {
  description = "Generate backend configuration files for layers"
  type        = bool
  default     = true
}

variable "backend_config_output_path" {
  description = "Output path for generated backend configuration files"
  type        = string
  default     = "./backends/aws"
}

# ============================================================================
# IAM Policy Variables
# ============================================================================

variable "create_access_policy" {
  description = "Create an IAM policy for backend access"
  type        = bool
  default     = true
}