# Enhanced Cluster Autoscaler Module with DaemonSet Support
# Fixes for Fluent Bit scheduling issues and improved scaling behavior

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

# DATA SOURCES
data "aws_caller_identity" "current" {}

# IAM ROLE FOR CLUSTER AUTOSCALER (conditional creation)
resource "aws_iam_role" "cluster_autoscaler" {
  count = var.external_irsa_role_arn == null ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler-role"

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
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = [
              "system:serviceaccount:kube-system:${var.service_account_name}",
              "system:serviceaccount:kube-system:cluster-autoscaler-aws-cluster-autoscaler"
            ]
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-cluster-autoscaler-role"
    Purpose = "Cluster Autoscaler IRSA Role"
  })
}

# IAM POLICY FOR CLUSTER AUTOSCALER (conditional creation)
resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.external_irsa_role_arn == null ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler-policy"
  description = "Policy for cluster autoscaler to manage ASG scaling"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-cluster-autoscaler-policy"
    Purpose = "Cluster Autoscaler IAM Policy"
  })
}

#  ATTACH POLICY TO ROLE (conditional)
resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.external_irsa_role_arn == null ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
  role       = aws_iam_role.cluster_autoscaler[0].name
}

# Local to determine the role ARN to use
locals {
  cluster_autoscaler_role_arn = var.external_irsa_role_arn != null ? var.external_irsa_role_arn : aws_iam_role.cluster_autoscaler[0].arn
}

# KUBERNETES SERVICE ACCOUNT
resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = var.service_account_name
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = local.cluster_autoscaler_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "cluster-autoscaler"
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/part-of"    = var.cluster_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}


# ENHANCED HELM RELEASE FOR CLUSTER AUTOSCALER WITH DAEMONSET SUPPORT
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.helm_chart_version
  namespace  = "kube-system"
  timeout    = 600 # Increased timeout for better reliability

  # Use values block for complex configurations
  values = [
    yamlencode({
      serviceAccount = {
        create = false  # Use the service account created by Terraform
        name   = var.service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = local.cluster_autoscaler_role_arn
        }
      }
    })
  ]

  # Core configuration
  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  # CRITICAL: DaemonSet support configuration
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false" # CRITICAL: Allow scaling for DaemonSets like Fluent Bit
  }

  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = var.skip_nodes_with_local_storage
  }

  # Enhanced scaling behavior for DaemonSets
  set {
    name  = "extraArgs.scale-down-enabled"
    value = var.scale_down_enabled
  }

  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = var.scale_down_delay_after_add
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = var.scale_down_unneeded_time
  }

  # Improved resource utilization thresholds
  set {
    name  = "extraArgs.scale-down-utilization-threshold"
    value = "0.5" # Scale down when utilization is below 50%
  }

  set {
    name  = "extraArgs.max-node-provision-time"
    value = "15m" # Allow more time for node provisioning
  }

  # Logging for better troubleshooting
  set {
    name  = "extraArgs.v"
    value = "4" # Verbose logging
  }

  set {
    name  = "extraArgs.logtostderr"
    value = "true"
  }

  set {
    name  = "extraArgs.stderrthreshold"
    value = "info"
  }

  # Resource management with higher limits for better performance
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "300Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "300m" # Increased from 200m
  }

  set {
    name  = "resources.limits.memory"
    value = "500Mi" # Increased from 300Mi
  }

  # Security context
  set {
    name  = "securityContext.runAsNonRoot"
    value = "true"
  }

  set {
    name  = "securityContext.runAsUser"
    value = "65534"
  }

  # Node selection for stability
  set {
    name  = "nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # Prefer system nodes when available
  set {
    name  = "nodeSelector.workload-type"
    value = "system"
  }

  # Enhanced tolerations for system workloads
  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for system node group workload-type taint
  set {
    name  = "tolerations[1].key"
    value = "workload-type"
  }

  set {
    name  = "tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[1].value"
    value = "system"
  }

  set {
    name  = "tolerations[1].effect"
    value = "NoSchedule"
  }

  # Toleration for system node group dedicated taint
  set {
    name  = "tolerations[2].key"
    value = "dedicated"
  }

  set {
    name  = "tolerations[2].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[2].value"
    value = "shared-services"
  }

  set {
    name  = "tolerations[2].effect"
    value = "NoSchedule"
  }

  # Priority class for system workloads
  set {
    name  = "priorityClassName"
    value = "system-cluster-critical"
  }

  # Pod disruption budget for high availability
  set {
    name  = "podDisruptionBudget.enabled"
    value = "true"
  }

  set {
    name  = "podDisruptionBudget.maxUnavailable"
    value = "0"
  }

  # Replica count for high availability
  set {
    name  = "replicaCount"
    value = "1" # Single replica is fine for cluster-autoscaler
  }

  depends_on = [
    kubernetes_service_account.cluster_autoscaler,
    aws_iam_role_policy_attachment.cluster_autoscaler
  ]
}

# This null_resource ensures the Helm-created service account has the correct IRSA annotation
resource "null_resource" "fix_service_account_annotation" {
  depends_on = [helm_release.cluster_autoscaler]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for the Helm chart to create its service account
      sleep 10
      
      # Add IRSA annotation to the Helm-created service account if it exists and lacks the annotation
      if kubectl get serviceaccount cluster-autoscaler-aws-cluster-autoscaler -n kube-system >/dev/null 2>&1; then
        if ! kubectl get serviceaccount cluster-autoscaler-aws-cluster-autoscaler -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | grep -q "${local.cluster_autoscaler_role_arn}"; then
          kubectl annotate serviceaccount cluster-autoscaler-aws-cluster-autoscaler -n kube-system "eks.amazonaws.com/role-arn=${local.cluster_autoscaler_role_arn}" --overwrite
          # Restart the deployment to pick up the new annotation
          kubectl rollout restart deployment cluster-autoscaler-aws-cluster-autoscaler -n kube-system
        fi
      fi
    EOT
  }

  # Re-run when the Helm release changes
  triggers = {
    helm_release_version = helm_release.cluster_autoscaler.version
    role_arn            = local.cluster_autoscaler_role_arn
  }
}
