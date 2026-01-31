# ============================================================================
# S3 Module Variables
# ============================================================================

# ============================================================================
# Basic Configuration
# ============================================================================

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric."
  }
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects (use carefully in production)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "block_public_access" {
  description = "Block all public access to the bucket (recommended: true)"
  type        = bool
  default     = true
}

variable "versioning_enabled" {
  description = "Enable versioning for the bucket"
  type        = bool
  default     = false
}

variable "encryption" {
  description = "Server-side encryption configuration"
  type = object({
    type       = string           # "AES256" (SSE-S3) or "aws:kms" (SSE-KMS)
    kms_key_id = optional(string) # Required if type is "aws:kms"
  })
  default = {
    type       = "AES256"
    kms_key_id = null
  }

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption.type)
    error_message = "Encryption type must be 'AES256' or 'aws:kms'."
  }
}

# ============================================================================
# Lifecycle & Cost Optimization
# ============================================================================

variable "lifecycle_rules" {
  description = "Lifecycle rules for object transitions and expiration"
  type = object({
    # Current object transitions
    transition_standard_ia      = optional(number) # Days before transitioning to Standard-IA (min 30)
    transition_glacier_instant  = optional(number) # Days before transitioning to Glacier Instant (min 30)
    transition_glacier_flexible = optional(number) # Days before transitioning to Glacier Flexible (min 90)
    transition_deep_archive     = optional(number) # Days before transitioning to Deep Archive (min 180)
    expiration                  = optional(number) # Days before deleting objects

    # Noncurrent version transitions (for versioned buckets)
    noncurrent_version_transition_ia      = optional(number)
    noncurrent_version_transition_glacier = optional(number)
    noncurrent_version_expiration         = optional(number)

    # Cleanup
    abort_incomplete_multipart_upload_days = optional(number) # Cleanup incomplete uploads after N days
  })
  default = {}

  validation {
    condition = (
      try(var.lifecycle_rules.transition_standard_ia, null) == null ||
      try(var.lifecycle_rules.transition_standard_ia >= 30, false)
    )
    error_message = "transition_standard_ia must be at least 30 days (AWS requirement)."
  }

  validation {
    condition = (
      try(var.lifecycle_rules.transition_glacier_instant, null) == null ||
      try(var.lifecycle_rules.transition_glacier_instant >= 30, false)
    )
    error_message = "transition_glacier_instant must be at least 30 days (AWS requirement)."
  }

  validation {
    condition = (
      try(var.lifecycle_rules.transition_glacier_flexible, null) == null ||
      try(var.lifecycle_rules.transition_glacier_flexible >= 90, false)
    )
    error_message = "transition_glacier_flexible must be at least 90 days (AWS requirement)."
  }

  validation {
    condition = (
      try(var.lifecycle_rules.transition_deep_archive, null) == null ||
      try(var.lifecycle_rules.transition_deep_archive >= 180, false)
    )
    error_message = "transition_deep_archive must be at least 180 days (AWS requirement)."
  }
}

variable "intelligent_tiering" {
  description = "Intelligent-Tiering configuration for automatic cost optimization"
  type = object({
    enabled                       = bool
    archive_access_tier_days      = optional(number) # Move to Archive Access after N days (min 90)
    deep_archive_access_tier_days = optional(number) # Move to Deep Archive after N days (min 180)
  })
  default = {
    enabled                       = false
    archive_access_tier_days      = 0
    deep_archive_access_tier_days = 0
  }

  validation {
    condition = (
      !var.intelligent_tiering.enabled ||
      var.intelligent_tiering.archive_access_tier_days == 0 ||
      var.intelligent_tiering.archive_access_tier_days >= 90
    )
    error_message = "archive_access_tier_days must be at least 90 days when enabled."
  }

  validation {
    condition = (
      !var.intelligent_tiering.enabled ||
      var.intelligent_tiering.deep_archive_access_tier_days == 0 ||
      var.intelligent_tiering.deep_archive_access_tier_days >= 180
    )
    error_message = "deep_archive_access_tier_days must be at least 180 days when enabled."
  }
}

# ============================================================================
# Logging & Monitoring
# ============================================================================

variable "logging" {
  description = "S3 access logging configuration"
  type = object({
    enabled       = bool
    target_bucket = optional(string)
    target_prefix = optional(string)
  })
  default = {
    enabled       = false
    target_bucket = null
    target_prefix = null
  }
}

# ============================================================================
# CORS Configuration
# ============================================================================

variable "cors_rules" {
  description = "CORS rules for the bucket (e.g., for web access)"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}

# ============================================================================
# Bucket Policy
# ============================================================================

variable "bucket_policy" {
  description = "JSON bucket policy (optional)"
  type        = string
  default     = null
}

# ============================================================================
# Object Lock (Compliance)
# ============================================================================

variable "object_lock" {
  description = "Object lock configuration for compliance (WORM - Write Once Read Many)"
  type = object({
    enabled = bool
    mode    = optional(string) # "GOVERNANCE" or "COMPLIANCE"
    days    = optional(number) # Retention period in days
  })
  default = {
    enabled = false
    mode    = null
    days    = null
  }

  validation {
    condition = (
      !var.object_lock.enabled ||
      contains(["GOVERNANCE", "COMPLIANCE"], coalesce(var.object_lock.mode, "GOVERNANCE"))
    )
    error_message = "Object lock mode must be 'GOVERNANCE' or 'COMPLIANCE' when enabled."
  }
}
