# =============================================================================
# IAM Roles for Service Accounts (IRSA) - Per Client
# =============================================================================

# =============================================================================
# Fluent Bit IAM Role
# =============================================================================

resource "aws_iam_role" "fluent_bit" {
  name = local.fluent_bit_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${local.namespace}:fluent-bit"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name         = local.fluent_bit_role_name
    Client       = var.client_name
    Tier         = var.client_tier
    Service      = "fluent-bit"
    ManagedBy    = "terraform"
  })
}

resource "aws_iam_policy" "fluent_bit_s3" {
  name        = "${local.fluent_bit_role_name}-s3"
  description = "S3 access for Fluent Bit - ${var.client_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${var.shared_logs_bucket_arn}/${local.logs_prefix}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          var.shared_logs_bucket_arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.logs_prefix}*"]
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fluent_bit_s3" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = aws_iam_policy.fluent_bit_s3.arn
}

# =============================================================================
# Loki IAM Role
# =============================================================================

resource "aws_iam_role" "loki" {
  count = var.enable_loki ? 1 : 0
  name  = local.loki_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${local.namespace}:loki-*"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name      = local.loki_role_name
    Client    = var.client_name
    Tier      = var.client_tier
    Service   = "loki"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_policy" "loki_s3" {
  count       = var.enable_loki ? 1 : 0
  name        = "${local.loki_role_name}-s3"
  description = "S3 access for Loki - ${var.client_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          var.shared_logs_bucket_arn,
          "${var.shared_logs_bucket_arn}/${local.logs_prefix}*"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  count      = var.enable_loki ? 1 : 0
  role       = aws_iam_role.loki[0].name
  policy_arn = aws_iam_policy.loki_s3[0].arn
}

# =============================================================================
# Tempo IAM Role
# =============================================================================

resource "aws_iam_role" "tempo" {
  count = var.enable_tempo ? 1 : 0
  name  = local.tempo_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${local.namespace}:tempo"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name      = local.tempo_role_name
    Client    = var.client_name
    Tier      = var.client_tier
    Service   = "tempo"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_policy" "tempo_s3" {
  count       = var.enable_tempo ? 1 : 0
  name        = "${local.tempo_role_name}-s3"
  description = "S3 access for Tempo - ${var.client_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          var.shared_traces_bucket_arn,
          "${var.shared_traces_bucket_arn}/${local.traces_prefix}*"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "tempo_s3" {
  count      = var.enable_tempo ? 1 : 0
  role       = aws_iam_role.tempo[0].name
  policy_arn = aws_iam_policy.tempo_s3[0].arn
}
