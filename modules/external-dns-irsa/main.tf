# External DNS IRSA Module
# Creates IAM role for ExternalDNS to manage Route53 records

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.oidc.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [data.aws_iam_openid_connect_provider.oidc.arn]
      type        = "Federated"
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = var.route53_zone_arns
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }

  # Optional: Tag-based permissions for multi-tenant setups
  dynamic "statement" {
    for_each = var.enable_txt_ownership_id ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "route53:GetChange"
      ]
      resources = ["arn:aws:route53:::change/*"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json

  tags = {
    Name = "${var.cluster_name}-external-dns"
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns"
  path        = "/"
  description = "IAM policy for ExternalDNS to manage Route53 records"
  policy      = data.aws_iam_policy_document.external_dns.json

  tags = {
    Name = "${var.cluster_name}-external-dns"
  }
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}
