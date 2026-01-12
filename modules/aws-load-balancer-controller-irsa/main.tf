data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# IAM policy document for AWS Load Balancer Controller
data "aws_iam_policy_document" "aws_load_balancer_controller" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:GetIpamPoolCidrs",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:DescribeProtection",
      "shield:GetSubscriptionState",
      "shield:DescribeSubscription",
      "shield:ListProtections",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestedRegion"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "Null"
      variable = "aws:RequestedRegion"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestedRegion"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyListener",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "Null"
      variable = "aws:RequestedRegion"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values = [
        "CreateTargetGroup",
        "CreateLoadBalancer",
      ]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestedRegion"
      values   = ["false"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "tag:GetResources"
      values   = ["ResourceGroupsTaggingAPI"]
    }
  }
}

# Create IAM policy
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.aws_iam_policy_document.aws_load_balancer_controller.json

  tags = {
    Name = "${var.cluster_name}-aws-load-balancer-controller"
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${var.cluster_name}-aws-load-balancer-controller"
  }
}

# Attach the custom policy to the role
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}
