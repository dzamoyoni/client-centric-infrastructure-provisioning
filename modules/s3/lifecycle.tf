# ============================================================================
# S3 Lifecycle Policies - Cost Optimization
# ============================================================================
# Purpose: Automatic transitions and expiration for cost optimization
# Supports:
#   - Fixed lifecycle transitions (Standard → IA → Glacier)
#   - Intelligent-Tiering (AWS-managed optimization)
#   - Noncurrent version transitions (for versioned buckets)
#   - Incomplete multipart upload cleanup
# ============================================================================

# ============================================================================
# Intelligent-Tiering Configuration (Recommended for Observability)
# ============================================================================

resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count = var.intelligent_tiering.enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"

  # Archive Access tier (90-180 days no access)
  dynamic "tiering" {
    for_each = var.intelligent_tiering.archive_access_tier_days > 0 ? [1] : []
    content {
      access_tier = "ARCHIVE_ACCESS"
      days        = var.intelligent_tiering.archive_access_tier_days
    }
  }

  # Deep Archive Access tier (180+ days no access)
  dynamic "tiering" {
    for_each = var.intelligent_tiering.deep_archive_access_tier_days > 0 ? [1] : []
    content {
      access_tier = "DEEP_ARCHIVE_ACCESS"
      days        = var.intelligent_tiering.deep_archive_access_tier_days
    }
  }
}

# ============================================================================
# Lifecycle Rules (Fixed Transitions and Expiration)
# ============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  # Only create if lifecycle rules are defined or intelligent-tiering needs storage class
  count = (
    var.lifecycle_rules.expiration != null ||
    var.lifecycle_rules.transition_standard_ia != null ||
    var.lifecycle_rules.transition_glacier_instant != null ||
    var.lifecycle_rules.transition_glacier_flexible != null ||
    var.lifecycle_rules.transition_deep_archive != null ||
    var.lifecycle_rules.noncurrent_version_expiration != null ||
    var.lifecycle_rules.abort_incomplete_multipart_upload_days != null ||
    var.intelligent_tiering.enabled
  ) ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Rule for current objects
  rule {
    id     = "main-lifecycle-rule"
    status = "Enabled"

    # Filter - apply to all objects (required by AWS provider)
    filter {}

    # ========================================================================
    # Intelligent-Tiering Storage Class (if enabled)
    # ========================================================================
    dynamic "transition" {
      for_each = var.intelligent_tiering.enabled ? [1] : []
      content {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }

    # ========================================================================
    # Fixed Transitions (if not using intelligent-tiering)
    # ========================================================================

    # Transition to Standard-IA (minimum 30 days)
    dynamic "transition" {
      for_each = !var.intelligent_tiering.enabled && var.lifecycle_rules.transition_standard_ia != null ? [1] : []
      content {
        days          = var.lifecycle_rules.transition_standard_ia
        storage_class = "STANDARD_IA"
      }
    }

    # Transition to Glacier Instant Retrieval (minimum 30 days after IA)
    dynamic "transition" {
      for_each = !var.intelligent_tiering.enabled && var.lifecycle_rules.transition_glacier_instant != null ? [1] : []
      content {
        days          = var.lifecycle_rules.transition_glacier_instant
        storage_class = "GLACIER_IR"
      }
    }

    # Transition to Glacier Flexible Retrieval (minimum 90 days)
    dynamic "transition" {
      for_each = !var.intelligent_tiering.enabled && var.lifecycle_rules.transition_glacier_flexible != null ? [1] : []
      content {
        days          = var.lifecycle_rules.transition_glacier_flexible
        storage_class = "GLACIER"
      }
    }

    # Transition to Glacier Deep Archive (minimum 180 days)
    dynamic "transition" {
      for_each = !var.intelligent_tiering.enabled && var.lifecycle_rules.transition_deep_archive != null ? [1] : []
      content {
        days          = var.lifecycle_rules.transition_deep_archive
        storage_class = "DEEP_ARCHIVE"
      }
    }

    # ========================================================================
    # Expiration (delete objects after retention period)
    # ========================================================================
    dynamic "expiration" {
      for_each = var.lifecycle_rules.expiration != null ? [1] : []
      content {
        days = var.lifecycle_rules.expiration
      }
    }

    # ========================================================================
    # Cleanup incomplete multipart uploads (cost saver)
    # ========================================================================
    dynamic "abort_incomplete_multipart_upload" {
      for_each = var.lifecycle_rules.abort_incomplete_multipart_upload_days != null ? [1] : []
      content {
        days_after_initiation = var.lifecycle_rules.abort_incomplete_multipart_upload_days
      }
    }
  }

  # ========================================================================
  # Rule for noncurrent versions (versioned buckets only)
  # ========================================================================
  dynamic "rule" {
    for_each = var.versioning_enabled && (
      var.lifecycle_rules.noncurrent_version_expiration != null ||
      var.lifecycle_rules.noncurrent_version_transition_ia != null ||
      var.lifecycle_rules.noncurrent_version_transition_glacier != null
    ) ? [1] : []

    content {
      id     = "noncurrent-version-lifecycle"
      status = "Enabled"

      # Filter - apply to all objects (required by AWS provider)
      filter {}

      # Transition noncurrent versions to Standard-IA
      dynamic "noncurrent_version_transition" {
        for_each = var.lifecycle_rules.noncurrent_version_transition_ia != null ? [1] : []
        content {
          noncurrent_days = var.lifecycle_rules.noncurrent_version_transition_ia
          storage_class   = "STANDARD_IA"
        }
      }

      # Transition noncurrent versions to Glacier
      dynamic "noncurrent_version_transition" {
        for_each = var.lifecycle_rules.noncurrent_version_transition_glacier != null ? [1] : []
        content {
          noncurrent_days = var.lifecycle_rules.noncurrent_version_transition_glacier
          storage_class   = "GLACIER"
        }
      }

      # Delete noncurrent versions after retention
      dynamic "noncurrent_version_expiration" {
        for_each = var.lifecycle_rules.noncurrent_version_expiration != null ? [1] : []
        content {
          noncurrent_days = var.lifecycle_rules.noncurrent_version_expiration
        }
      }
    }
  }
}
