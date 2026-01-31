# ============================================================================
# Layer 00: Bootstrap Variables
# ============================================================================

# ============================================================================
# Core Configuration
# ============================================================================

variable "organization_name" {
  description = "Organization name (used in resource naming)"
  type        = string
  default     = "myorg"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "contact_email" {
  description = "Contact email for infrastructure notifications"
  type        = string
  default     = "platform-team@example.com"
}

# ============================================================================
# Observability Configuration
# ============================================================================

variable "logs_retention_days" {
  description = "Retention period for logs in days"
  type        = number
  default     = 180

  validation {
    condition     = var.logs_retention_days >= 7 && var.logs_retention_days <= 365
    error_message = "Logs retention days must be between 7 and 365."
  }
}

variable "metrics_retention_days" {
  description = "Retention period for metrics in days (shorter retention for cost optimization)"
  type        = number
  default     = 14

  validation {
    condition     = var.metrics_retention_days >= 7 && var.metrics_retention_days <= 365
    error_message = "Metrics retention days must be between 7 and 365."
  }
}

variable "traces_retention_days" {
  description = "Retention period for traces in days (shortest retention for cost optimization)"
  type        = number
  default     = 7

  validation {
    condition     = var.traces_retention_days >= 7 && var.traces_retention_days <= 365
    error_message = "Traces retention days must be between 7 and 365."
  }
}

# ============================================================================
# Client Configuration
# ============================================================================

variable "clients" {
  description = "Map of clients for observability bucket provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string

    metadata = object({
      full_name     = string
      industry      = string
      contact_email = string
      compliance    = list(string)
      cost_center   = string
      business_unit = string
    })
  }))
  default = {}
}

# ============================================================================
# Tagging Configuration (Bootstrap Layer)
# ============================================================================

variable "dr_tier" {
  description = "Disaster Recovery tier for bootstrap infrastructure"
  type        = string
  default     = "Tier-1"

  validation {
    condition     = contains(["Tier-1", "Tier-2", "Tier-3", "Tier-4"], var.dr_tier)
    error_message = "DR tier must be Tier-1, Tier-2, Tier-3, or Tier-4."
  }
}

variable "rpo" {
  description = "Recovery Point Objective"
  type        = string
  default     = "1h"
}

variable "rto" {
  description = "Recovery Time Objective"
  type        = string
  default     = "1h"
}

variable "resource_type" {
  description = "Type of AWS resource"
  type        = string
  default     = "S3"
}

variable "security_level" {
  description = "Security level classification"
  type        = string
  default     = "Critical"

  validation {
    condition     = contains(["Low", "Medium", "High", "Critical"], var.security_level)
    error_message = "Security level must be Low, Medium, High, or Critical."
  }
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "IT-Infrastructure"
}

variable "business_unit" {
  description = "Business unit or division"
  type        = string
  default     = "Platform-Engineering"
}

variable "owner" {
  description = "Owner or responsible team"
  type        = string
  default     = "Platform-Engineering"
}

variable "backup_required" {
  description = "Whether backup is required"
  type        = string
  default     = "true"

  validation {
    condition     = contains(["true", "false"], var.backup_required)
    error_message = "Backup required must be true or false."
  }
}

variable "data_classification" {
  description = "Data classification level"
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted", "Secret"], var.data_classification)
    error_message = "Data classification must be Public, Internal, Confidential, Restricted, or Secret."
  }
}

variable "critical_infrastructure" {
  description = "Whether this is critical infrastructure"
  type        = string
  default     = "true"

  validation {
    condition     = contains(["true", "false"], var.critical_infrastructure)
    error_message = "Critical infrastructure must be true or false."
  }
}

variable "deployment_phase" {
  description = "Deployment phase identifier"
  type        = string
  default     = "Phase-0-Bootstrap"
}
