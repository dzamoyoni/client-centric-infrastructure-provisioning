# ============================================================================
# Per-Client Observability Buckets
# ============================================================================
# Creates S3 buckets for each enabled client:
#   1. Logs bucket (application, infrastructure, audit logs)
#   2. Metrics bucket (Prometheus, CloudWatch metrics)
#   3. Traces bucket (distributed tracing data)
#
# Features:
#   - Intelligent-Tiering for cost optimization (recommended)
#   - 180-day retention
#   - No versioning (cost optimization for observability data)
#   - Client-specific tagging
#
# Layer 06-Observability will read these bucket names via remote state
# ============================================================================

locals {
  # Generate bucket configurations for each client
  observability_buckets = flatten([
    for client_name, client_config in local.enabled_clients : [
      {
        client      = client_name
        type        = "logs"
        retention   = var.logs_retention_days
        bucket_name = "${client_name}-logs-${var.region}-${var.environment}"
        description = "Application and infrastructure logs for ${client_name}"
      },
      {
        client      = client_name
        type        = "metrics"
        retention   = var.metrics_retention_days
        bucket_name = "${client_name}-metrics-${var.region}-${var.environment}"
        description = "Prometheus and CloudWatch metrics for ${client_name}"
      },
      {
        client      = client_name
        type        = "traces"
        retention   = var.traces_retention_days
        bucket_name = "${client_name}-traces-${var.region}-${var.environment}"
        description = "Distributed tracing data for ${client_name}"
      }
    ]
  ])

  # Convert to map for for_each
  observability_buckets_map = {
    for bucket in local.observability_buckets :
    "${bucket.client}-${bucket.type}" => bucket
  }
}

# ============================================================================
# Observability Buckets (Logs, Metrics, Traces)
# ============================================================================

module "observability_buckets" {
  source = "../../../../../../../modules/s3"

  for_each = local.observability_buckets_map

  bucket_name = each.value.bucket_name

  # No versioning for observability data (cost optimization)
  versioning_enabled = false

  # Intelligent-Tiering for automatic cost optimization (RECOMMENDED)
  intelligent_tiering = {
    enabled                       = true
    archive_access_tier_days      = 90  # Auto-archive after 90 days no access
    deep_archive_access_tier_days = 180 # Deep archive after 180 days no access
  }

  # Expiration and cleanup
  lifecycle_rules = {
    # Delete after retention period
    expiration = each.value.retention

    # Cleanup incomplete multipart uploads (cost saver)
    abort_incomplete_multipart_upload_days = 7
  }

  # SSE-S3 encryption (no additional cost)
  encryption = {
    type = "AES256"
  }

  # Security: Block all public access
  block_public_access = true

  # Industrial tagging with client-specific tags (sanitized for LocalStack)
  tags = merge(
    local.sanitized_standard_tags,
    local.client_tags[each.value.client],
    {
      Name               = each.value.bucket_name
      BucketType         = title(each.value.type) # Logs/Metrics/Traces
      DataRetention      = replace("${each.value.retention}-days", " ", "-")
      DataClassification = "Internal"
      Purpose            = replace(replace(replace(each.value.description, " ", "-"), "&", "and"), ":", "-")
      LifecyclePolicy    = replace("Intelligent-Tiering-${each.value.retention}d-Delete", " ", "-")
      CostOptimization   = "Intelligent-Tiering-Enabled"
    }
  )
}

# ============================================================================
# Bucket Structure Documentation (for Layer 06-Observability)
# ============================================================================

# Expected directory structure in buckets (created by observability tools):
#
# Logs Bucket (client-name-logs-us-east-2-production):
# ├── infrastructure/
# │   ├── eks/
# │   │   ├── pods/                  # Pod logs from Fluent Bit
# │   │   ├── nodes/                 # Node logs
# │   │   └── system/                # kube-system logs
# │   ├── rds/
# │   │   ├── postgresql/            # PostgreSQL logs (future)
# │   │   └── slow-query/
# │   ├── ec2/
# │   │   └── postgresql/            # EC2-hosted PostgreSQL logs (current)
# │   └── vpc/
# │       └── flow-logs/
# ├── application/
# │   └── {service-name}/            # Application logs
# │       └── year=YYYY/month=MM/day=DD/hour=HH/
# └── audit/
#     └── cloudtrail/
#
# Metrics Bucket (client-name-metrics-us-east-2-production):
# ├── prometheus/                     # Prometheus remote write
# │   └── year=YYYY/month=MM/day=DD/
# ├── database/
# │   ├── postgresql-exporter/       # PostgreSQL metrics
# │   └── rds-exporter/              # RDS metrics (future)
# └── cloudwatch/
#     └── year=YYYY/month=MM/day=DD/
#
# Traces Bucket (client-name-traces-us-east-2-production):
# ├── tempo/                         # Tempo backend storage (if used)
# │   └── year=YYYY/month=MM/day=DD/
# ├── jaeger/                        # Jaeger backend storage
# │   └── year=YYYY/month=MM/day=DD/
# └── opentelemetry/
#     └── year=YYYY/month=MM/day=DD/
