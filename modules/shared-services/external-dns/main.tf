# External DNS Module
# Deploys External DNS with Helm for Route53 automation

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "external_irsa_role_arn" {
  description = "External IRSA role ARN. If provided, the module will use this instead of creating its own IRSA role."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "oidc_provider_id" {
  description = "ID of the OIDC provider"
  type        = string
}

variable "service_account_name" {
  description = "Name of the service account"
  type        = string
}

variable "helm_chart_version" {
  description = "Version of External DNS Helm chart"
  type        = string
}

variable "domain_filters" {
  description = "List of domain filters for External DNS"
  type        = list(string)
  default     = []
}

variable "policy" {
  description = "External DNS policy (sync or upsert-only)"
  type        = string
  default     = "upsert-only"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# IAM Role for External DNS (conditional creation)
resource "aws_iam_role" "external_dns" {
  count = var.external_irsa_role_arn == null ? 1 : 0
  name  = "${var.cluster_name}-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:kube-system:${var.service_account_name}"
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-external-dns-role"
    Purpose = "External DNS IRSA Role"
  })
}

# IAM Policy for External DNS (conditional creation)
resource "aws_iam_policy" "external_dns" {
  count       = var.external_irsa_role_arn == null ? 1 : 0
  name        = "${var.cluster_name}-ExternalDNSPolicy"
  description = "Policy for External DNS to manage Route53 records"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-ExternalDNSPolicy"
    Purpose = "External DNS IAM Policy"
  })
}

# Attach policy to role (conditional)
resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.external_irsa_role_arn == null ? 1 : 0
  policy_arn = aws_iam_policy.external_dns[0].arn
  role       = aws_iam_role.external_dns[0].name
}

# Local to determine the role ARN to use
locals {
  external_dns_role_arn = var.external_irsa_role_arn != null ? var.external_irsa_role_arn : aws_iam_role.external_dns[0].arn
}

# Kubernetes service account
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = var.service_account_name
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = local.external_dns_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/part-of"    = var.cluster_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Helm release for External DNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.helm_chart_version
  namespace  = "kube-system"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = var.region
  }

  set {
    name  = "policy"
    value = var.policy
  }

  set {
    name  = "registry"
    value = "txt"
  }

  set {
    name  = "txtOwnerId"
    value = "${var.cluster_name}-external-dns"
  }

  # Domain filters
  dynamic "set" {
    for_each = var.domain_filters
    content {
      name  = "domainFilters[${set.key}]"
      value = set.value
    }
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = var.service_account_name
  }

  # Resource management
  set {
    name  = "resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "resources.requests.memory"
    value = "50Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "resources.limits.memory"
    value = "100Mi"
  }

  depends_on = [
    kubernetes_service_account.external_dns
  ]
}

# Outputs
output "iam_role_arn" {
  description = "ARN of the External DNS IAM role"
  value       = local.external_dns_role_arn
}

output "service_account_name" {
  description = "Name of the External DNS service account"
  value       = kubernetes_service_account.external_dns.metadata[0].name
}
