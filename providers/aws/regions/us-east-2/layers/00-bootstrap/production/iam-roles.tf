# ============================================================================
# IAM Roles for Observability Services
# ============================================================================
# Creates IAM roles with least-privilege access for:
#   1. Prometheus - write metrics to S3
#   2. Fluent Bit - write logs to S3
#   3. Tempo/Jaeger - write traces to S3
#
# These roles will be assumed by observability services running in EKS
# (via IRSA - IAM Roles for Service Accounts)
# ============================================================================

# ============================================================================
# IAM Role for Prometheus (Metrics Writer)
# ============================================================================

resource "aws_iam_role" "prometheus_s3_writer" {
  name        = "prometheus-s3-writer-${var.environment}"
  description = "Role for Prometheus to write metrics to S3 buckets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com" # For EC2-hosted Prometheus
        }
        Action = "sts:AssumeRole"
      },
      # Future: Add IRSA (EKS) support
      # {
      #   Effect = "Allow"
      #   Principal = {
      #     Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${eks_oidc_provider}"
      #   }
      #   Action = "sts:AssumeRoleWithWebIdentity"
      #   Condition = {
      #     StringEquals = {
      #       "${eks_oidc_provider}:sub" = "system:serviceaccount:monitoring:prometheus"
      #     }
      #   }
      # }
    ]
  })

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "prometheus-s3-writer"
      ResourceType = "IAM-Role"
      Purpose      = "Prometheus-Metrics-Storage"
    }
  )
}

# Policy: Write to all metrics buckets
resource "aws_iam_role_policy" "prometheus_metrics_write" {
  name = "prometheus-metrics-write"
  role = aws_iam_role.prometheus_s3_writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteMetricsBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"  # For reading remote write WAL
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          "${bucket.bucket_arn}/*"
          if strcontains(key, "-metrics")
        ]
      },
      {
        Sid    = "ListMetricsBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          bucket.bucket_arn
          if strcontains(key, "-metrics")
        ]
      }
    ]
  })
}

# ============================================================================
# IAM Role for Fluent Bit (Logs Writer)
# ============================================================================

resource "aws_iam_role" "fluent_bit_s3_writer" {
  name        = "fluent-bit-s3-writer-${var.environment}"
  description = "Role for Fluent Bit to write logs to S3 buckets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "fluent-bit-s3-writer"
      ResourceType = "IAM-Role"
      Purpose      = "Fluent-Bit-Log-Storage"
    }
  )
}

# Policy: Write to all logs buckets
resource "aws_iam_role_policy" "fluent_bit_logs_write" {
  name = "fluent-bit-logs-write"
  role = aws_iam_role.fluent_bit_s3_writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogsBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          "${bucket.bucket_arn}/*"
          if strcontains(key, "-logs")
        ]
      },
      {
        Sid    = "ListLogsBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          bucket.bucket_arn
          if strcontains(key, "-logs")
        ]
      }
    ]
  })
}

# ============================================================================
# IAM Role for Tempo/Jaeger (Traces Writer)
# ============================================================================

resource "aws_iam_role" "tempo_s3_writer" {
  name        = "tempo-s3-writer-${var.environment}"
  description = "Role for Tempo/Jaeger to write traces to S3 buckets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "tempo-s3-writer"
      ResourceType = "IAM-Role"
      Purpose      = "Tempo-Trace-Storage"
    }
  )
}

# Policy: Write to all traces buckets
resource "aws_iam_role_policy" "tempo_traces_write" {
  name = "tempo-traces-write"
  role = aws_iam_role.tempo_s3_writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteTracesBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",      # For reading trace data
          "s3:DeleteObject"    # For compaction
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          "${bucket.bucket_arn}/*"
          if strcontains(key, "-traces")
        ]
      },
      {
        Sid    = "ListTracesBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          for key, bucket in module.observability_buckets :
          bucket.bucket_arn
          if strcontains(key, "-traces")
        ]
      }
    ]
  })
}

# ============================================================================
# IAM Instance Profiles (for EC2-hosted observability services)
# ============================================================================

resource "aws_iam_instance_profile" "prometheus" {
  name = "prometheus-s3-writer-${var.environment}"
  role = aws_iam_role.prometheus_s3_writer.name

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "prometheus-instance-profile"
      ResourceType = "IAM-Instance-Profile"
    }
  )
}

resource "aws_iam_instance_profile" "fluent_bit" {
  name = "fluent-bit-s3-writer-${var.environment}"
  role = aws_iam_role.fluent_bit_s3_writer.name

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "fluent-bit-instance-profile"
      ResourceType = "IAM-Instance-Profile"
    }
  )
}

resource "aws_iam_instance_profile" "tempo" {
  name = "tempo-s3-writer-${var.environment}"
  role = aws_iam_role.tempo_s3_writer.name

  tags = merge(
    module.tags.standard_tags,
    {
      Name         = "tempo-instance-profile"
      ResourceType = "IAM-Instance-Profile"
    }
  )
}
