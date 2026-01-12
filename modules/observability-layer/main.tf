# ============================================================================
# Observability Layer Module
# ============================================================================
# This module provides comprehensive observability infrastructure for
# Client EKS environments with:
# - Fluent Bit for log shipping to S3
# - Grafana Tempo for distributed tracing
# - Prometheus with remote write capabilities  
# - S3 backends for logs and traces
# - Tenant isolation and data partitioning
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# ============================================================================
# EBS CSI Driver Module (Dependency for Storage)
# ============================================================================

module "ebs_csi_driver" {
  source = "../ebs-csi-driver"

  cluster_name            = var.cluster_name
  node_group_role_names   = var.node_group_role_names
  create_gp2_storageclass = true
  make_gp2_default        = true
  create_gp3_storageclass = var.enable_gp3_storage

  tags = local.common_tags
}

# ============================================================================
# Local Variables and Configuration
# ============================================================================

locals {
  # Common tags applied to all resources
  common_tags = merge(var.common_tags, {
    Layer       = "Observability"
    ManagedBy   = "Terraform"
    Component   = "Observability-Stack"
    Region      = var.region
    Environment = var.environment
  })

  # Observability namespace
  observability_namespace = "istio-system"

  # S3 bucket naming
  logs_bucket_name   = "${var.project_name}-${var.region}-logs-${var.environment}"
  traces_bucket_name = "${var.project_name}-${var.region}-traces-${var.environment}"

  # Service account names
  fluent_bit_sa_name = "fluent-bit"
  tempo_sa_name      = "tempo"
  prometheus_sa_name = "prometheus"

  # Client tenant configurations
  tenant_configs = {
    for tenant in var.tenant_configs : tenant.name => {
      name      = tenant.name
      namespace = tenant.namespace
      labels    = tenant.labels
    }
  }
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get EKS cluster information
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# ============================================================================
# S3 Buckets for Logs and Traces - Using Standardized S3 Management
# ============================================================================

# Logs S3 Bucket - Using CPTWN S3 Management Module
module "logs_bucket" {
  source = "../s3-bucket-management"

  # Core configuration
  project_name   = var.project_name
  environment    = var.environment
  region         = var.region
  bucket_purpose = "logs"

  # Custom naming to maintain compatibility
  custom_bucket_name = local.logs_bucket_name

  # Logs-specific configuration with structured keys
  logs_retention_days        = var.logs_retention_days
  enable_intelligent_tiering = var.enable_intelligent_tiering
  enable_cost_metrics        = true
  enable_structured_keys     = true

  # Custom key patterns for logs
  custom_key_patterns = {
    logs = {
      enabled    = true
      pattern    = "logs/cluster=$${cluster_name}/tenant=$${tenant}/service=$${service}/year=%Y/month=%m/day=%d/hour=%H/fluent-bit-logs-%Y%m%d-%H%M%S-$$UUID.gz"
      partitions = ["cluster_name", "tenant", "service", "year", "month", "day", "hour"]
    }
  }

  # Advanced lifecycle patterns for log data
  lifecycle_key_patterns = {
    hot_logs = {
      enabled       = true
      filter_prefix = "logs/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration_days = var.logs_retention_days
    }
  }

  # Security configuration
  enable_versioning = true
  kms_key_id        = var.logs_kms_key_id

  # Cross-region replication for disaster recovery
  enable_cross_region_replication    = var.enable_cross_region_replication
  replication_destination_bucket_arn = var.logs_replication_bucket_arn

  # Monitoring and notifications
  enable_bucket_notifications = var.enable_bucket_monitoring
  enable_eventbridge          = var.enable_bucket_monitoring
  notification_topics         = var.logs_notification_topics

  # Standard tags
  common_tags = merge(local.common_tags, {
    Purpose = "Application and Infrastructure Logs"
    Type    = "Logs"
  })
}

# Traces S3 Bucket - Using S3 Management Module  
module "traces_bucket" {
  source = "../s3-bucket-management"

  # Core configuration
  project_name   = var.project_name
  environment    = var.environment
  region         = var.region
  bucket_purpose = "traces"

  # Custom naming to maintain compatibility
  custom_bucket_name = local.traces_bucket_name

  # Traces-specific configuration with structured keys
  traces_retention_days      = var.traces_retention_days
  enable_intelligent_tiering = var.enable_intelligent_tiering
  enable_cost_metrics        = true
  enable_structured_keys     = true

  # Custom key patterns for traces
  custom_key_patterns = {
    traces = {
      enabled    = true
      pattern    = "traces/cluster=$${cluster_name}/tenant=$${tenant}/service=$${service}/year=%Y/month=%m/day=%d/hour=%H/tempo-traces-%Y%m%d-%H%M%S-$$UUID.gz"
      partitions = ["cluster_name", "tenant", "service", "year", "month", "day", "hour"]
    }
  }

  # Advanced lifecycle patterns for trace data  
  lifecycle_key_patterns = {
    hot_traces = {
      enabled       = true
      filter_prefix = "traces/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration_days = var.traces_retention_days
    }
  }

  # Security configuration
  enable_versioning = true
  kms_key_id        = var.traces_kms_key_id

  # Cross-region replication for disaster recovery
  enable_cross_region_replication    = var.enable_cross_region_replication
  replication_destination_bucket_arn = var.traces_replication_bucket_arn

  # Monitoring and notifications
  enable_bucket_notifications = var.enable_bucket_monitoring
  enable_eventbridge          = var.enable_bucket_monitoring
  notification_topics         = var.traces_notification_topics

  # Standard tags
  common_tags = merge(local.common_tags, {
    Purpose = "Distributed Traces"
    Type    = "Traces"
  })
}

# ============================================================================
# IAM Roles and Policies for IRSA
# ============================================================================

# Fluent Bit IAM Policy
resource "aws_iam_policy" "fluent_bit_policy" {
  name        = "${var.project_name}-${var.region}-fluent-bit-policy"
  description = "Policy for Fluent Bit to access S3 and CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.logs_bucket.bucket_arn,
          "${module.logs_bucket.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })

  tags = local.common_tags
}

# Fluent Bit IAM Role
module "fluent_bit_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-${var.region}-fluent-bit-role"
  role_policy_arns = {
    fluent_bit_policy = aws_iam_policy.fluent_bit_policy.arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = var.cluster_oidc_issuer_arn
      namespace_service_accounts = ["${local.observability_namespace}:${local.fluent_bit_sa_name}"]
    }
  }

  tags = local.common_tags
}

# Tempo IAM Policy
resource "aws_iam_policy" "tempo_policy" {
  name        = "${var.project_name}-${var.region}-tempo-policy"
  description = "Policy for Tempo to access S3 for traces storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.traces_bucket.bucket_arn,
          "${module.traces_bucket.bucket_arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Tempo IAM Role
module "tempo_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-${var.region}-tempo-role"
  role_policy_arns = {
    tempo_policy = aws_iam_policy.tempo_policy.arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = var.cluster_oidc_issuer_arn
      namespace_service_accounts = ["${local.observability_namespace}:${local.tempo_sa_name}"]
    }
  }

  tags = local.common_tags
}

# ============================================================================
# Kubernetes Configurations
# ============================================================================

# Create ConfigMaps for Fluent Bit
resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = local.observability_namespace
    labels = merge(var.common_labels, {
      app = "fluent-bit"
    })
  }

  data = {
    "fluent-bit.conf" = templatefile("${path.module}/templates/fluent-bit.conf.tpl", {
      cluster_name   = var.cluster_name
      region         = var.region
      s3_bucket_name = module.logs_bucket.bucket_id
      tenant_configs = local.tenant_configs
    })

    "parsers.conf" = file("${path.module}/templates/parsers.conf")
  }

  depends_on = [module.logs_bucket]
}

# Create Service Account for Fluent Bit
resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = local.fluent_bit_sa_name
    namespace = local.observability_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.fluent_bit_irsa.iam_role_arn
    }
    labels = merge(var.common_labels, {
      app = "fluent-bit"
    })
  }
}

# Create Service Account for Tempo
resource "kubernetes_service_account" "tempo" {
  metadata {
    name      = local.tempo_sa_name
    namespace = local.observability_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.tempo_irsa.iam_role_arn
    }
    labels = merge(var.common_labels, {
      app = "tempo"
    })
  }
}

# ============================================================================
# Helm Charts Deployment
# ============================================================================

# Deploy Fluent Bit
resource "helm_release" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0

  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.fluent_bit_chart_version
  namespace  = local.observability_namespace

  values = [templatefile("${path.module}/templates/fluent-bit-values-enhanced.yaml.tpl", {
    service_account_name = kubernetes_service_account.fluent_bit.metadata[0].name
    cluster_name         = var.cluster_name
    region               = var.region
    s3_bucket_name       = module.logs_bucket.bucket_id
    image_tag            = var.fluent_bit_image_tag
    resources            = var.fluent_bit_resources
  })]

  depends_on = [
    kubernetes_config_map.fluent_bit_config,
    kubernetes_service_account.fluent_bit,
    module.fluent_bit_irsa
  ]
}

# Deploy Grafana Tempo
resource "helm_release" "tempo" {
  count = var.enable_tempo ? 1 : 0

  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version
  namespace  = local.observability_namespace

  values = [templatefile("${path.module}/templates/tempo-values.yaml.tpl", {
    service_account_name = kubernetes_service_account.tempo.metadata[0].name
    s3_bucket_name       = module.traces_bucket.bucket_id
    region               = var.region
    cluster_name         = var.cluster_name
    resources            = var.tempo_resources
  })]

  depends_on = [
    kubernetes_service_account.tempo,
    module.tempo_irsa
  ]
}

# Deploy Prometheus Stack
resource "helm_release" "prometheus_stack" {
  count = var.enable_prometheus ? 1 : 0

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_chart_version
  namespace  = local.observability_namespace
  timeout    = 600
  wait       = true

  values = [templatefile("${path.module}/templates/prometheus-values.yaml.tpl", {
    cluster_name          = var.cluster_name
    region                = var.region
    remote_write_url      = var.prometheus_remote_write_url
    remote_write_username = var.prometheus_remote_write_username
    remote_write_password = var.prometheus_remote_write_password
    tenant_configs        = local.tenant_configs
    storage_size          = var.prometheus_storage_size
    resources             = var.prometheus_resources
    enable_alertmanager   = var.enable_alertmanager
  })]
}

# ============================================================================
# Kiali for Service Mesh Visualization
# ============================================================================

resource "helm_release" "kiali" {
  count = var.enable_kiali ? 1 : 0

  name       = "kiali-server"
  repository = "https://kiali.org/helm-charts"
  chart      = "kiali-server"
  version    = var.kiali_chart_version
  namespace  = local.observability_namespace

  values = [templatefile("${path.module}/templates/kiali-values.yaml.tpl", {
    cluster_name   = var.cluster_name
    region         = var.region
    auth_strategy  = var.kiali_auth_strategy
    prometheus_url = var.enable_prometheus ? "http://prometheus-kube-prometheus-prometheus:9090" : var.external_prometheus_url
  })]

  # Signing key now set correctly in template

  # depends_on = [helm_release.prometheus_stack]  # Temporarily removed dependency
}

# ============================================================================
# PRODUCTION-GRADE GRAFANA DEPLOYMENT
# ============================================================================

# Generate random password for Grafana admin if not provided
resource "random_password" "grafana_admin_password" {
  count   = var.enable_grafana && var.grafana_admin_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Grafana admin credentials secret
resource "kubernetes_secret" "grafana_admin_secret" {
  count = var.enable_grafana ? 1 : 0

  metadata {
    name      = "grafana-admin-secret"
    namespace = local.observability_namespace
  }

  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin_password[0].result
  }

  type = "Opaque"
}

# Deploy Grafana (temporary or persistent)
resource "helm_release" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.3.7"
  namespace  = local.observability_namespace
  timeout    = 300

  values = [templatefile(
    var.grafana_temporary_mode ?
    "${path.module}/templates/grafana-temp-values.yaml.tpl" :
    "${path.module}/templates/grafana-values.yaml.tpl",
    {
      cluster_name = var.cluster_name
      region       = var.region
      storage_size = var.grafana_storage_size
    }
  )]

  depends_on = [
    kubernetes_secret.grafana_admin_secret[0]
  ]
}

# ============================================================================
# PRODUCTION-GRADE ALERTING
# ============================================================================

# Enhanced Monitoring Rules
resource "kubectl_manifest" "enhanced_monitoring_rules" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  yaml_body = templatefile("${path.module}/templates/prometheus-rules.yaml.tpl", {
    monitoring_namespace       = local.observability_namespace
    enable_postgres_monitoring = var.enable_postgres_monitoring
  })

  depends_on = [
    helm_release.prometheus_stack
  ]
}

# Cluster Autoscaler and DaemonSet Monitoring Rules
resource "kubectl_manifest" "cluster_autoscaler_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  yaml_body = templatefile("${path.module}/templates/cluster-autoscaler-monitoring.yaml.tpl", {
    monitoring_namespace = local.observability_namespace
  })

  depends_on = [
    helm_release.prometheus_stack
  ]
}

# Resource and Pod Scheduling Monitoring Rules
resource "kubectl_manifest" "resource_monitoring_rules" {
  count = 1 # Always enabled - critical for cluster health
  yaml_body = templatefile("${path.module}/templates/resource-monitoring-rules.yaml.tpl", {
    monitoring_namespace = local.observability_namespace
  })

  depends_on = [
    helm_release.prometheus_stack
  ]
}

# AlertManager Deployment
resource "helm_release" "alertmanager" {
  count      = var.enable_alertmanager ? 1 : 0
  name       = "alertmanager"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "alertmanager"
  version    = "1.9.0"
  namespace  = local.observability_namespace
  timeout    = 600

  values = [templatefile("${path.module}/templates/alertmanager-values.yaml.tpl", {
    monitoring_namespace       = local.observability_namespace
    slack_webhook_url          = var.slack_webhook_url
    alert_email                = var.alert_email
    alertmanager_storage_class = var.alertmanager_storage_class
    storage_size               = var.alertmanager_storage_size
    alertmanager_replicas      = var.alertmanager_replicas
    enable_security_context    = var.enable_security_context
    cluster_name               = var.cluster_name
    region                     = var.region
  })]

  depends_on = [
    helm_release.prometheus_stack
  ]
}

# ============================================================================
# NETWORK POLICIES FOR SECURITY
# ============================================================================

# Network policy for observability namespace
resource "kubernetes_network_policy" "observability_network_policy" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "observability-network-policy"
    namespace = local.observability_namespace
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/part-of" = "observability-stack"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = local.observability_namespace
          }
        }
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = local.observability_namespace
          }
        }
      }
    }

    # Allow egress to AWS services
    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}
