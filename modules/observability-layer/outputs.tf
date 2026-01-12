# ============================================================================
# Observability Layer Module Outputs
# ============================================================================

# ============================================================================
# S3 Bucket Information
# ============================================================================

output "logs_s3_bucket" {
  description = "S3 bucket information for logs"
  value = {
    id     = module.logs_bucket.bucket_id
    arn    = module.logs_bucket.bucket_arn
    bucket = module.logs_bucket.bucket_id
    region = module.logs_bucket.bucket_region
  }
}

output "traces_s3_bucket" {
  description = "S3 bucket information for traces"
  value = {
    id     = module.traces_bucket.bucket_id
    arn    = module.traces_bucket.bucket_arn
    bucket = module.traces_bucket.bucket_id
    region = module.traces_bucket.bucket_region
  }
}

# ============================================================================
# IAM Role Information
# ============================================================================

output "fluent_bit_role" {
  description = "Fluent Bit IAM role information"
  value = {
    arn  = module.fluent_bit_irsa.iam_role_arn
    name = module.fluent_bit_irsa.iam_role_name
  }
}

output "tempo_role" {
  description = "Tempo IAM role information"
  value = {
    arn  = module.tempo_irsa.iam_role_arn
    name = module.tempo_irsa.iam_role_name
  }
}

# ============================================================================
# Service Account Information
# ============================================================================

output "fluent_bit_service_account" {
  description = "Fluent Bit service account information"
  value = {
    name      = kubernetes_service_account.fluent_bit.metadata[0].name
    namespace = kubernetes_service_account.fluent_bit.metadata[0].namespace
  }
}

output "tempo_service_account" {
  description = "Tempo service account information"
  value = {
    name      = kubernetes_service_account.tempo.metadata[0].name
    namespace = kubernetes_service_account.tempo.metadata[0].namespace
  }
}

# ============================================================================
# Helm Release Information
# ============================================================================

output "fluent_bit_release" {
  description = "Fluent Bit Helm release information"
  value = var.enable_fluent_bit ? {
    name      = helm_release.fluent_bit[0].name
    namespace = helm_release.fluent_bit[0].namespace
    version   = helm_release.fluent_bit[0].version
    status    = helm_release.fluent_bit[0].status
  } : null
}

output "tempo_release" {
  description = "Tempo Helm release information"
  value = var.enable_tempo ? {
    name      = helm_release.tempo[0].name
    namespace = helm_release.tempo[0].namespace
    version   = helm_release.tempo[0].version
    status    = helm_release.tempo[0].status
  } : null
}

output "prometheus_release" {
  description = "Prometheus Helm release information"
  value = var.enable_prometheus ? {
    name      = helm_release.prometheus_stack[0].name
    namespace = helm_release.prometheus_stack[0].namespace
    version   = helm_release.prometheus_stack[0].version
    status    = helm_release.prometheus_stack[0].status
  } : null
}

output "kiali_release" {
  description = "Kiali Helm release information"
  value = var.enable_kiali ? {
    name      = helm_release.kiali[0].name
    namespace = helm_release.kiali[0].namespace
    version   = helm_release.kiali[0].version
    status    = helm_release.kiali[0].status
  } : null
}

# ============================================================================
# Endpoints and URLs
# ============================================================================

output "tempo_endpoint" {
  description = "Tempo endpoint for trace ingestion"
  value       = var.enable_tempo ? "http://tempo.${local.observability_namespace}.svc.cluster.local:3100" : null
}

output "prometheus_endpoint" {
  description = "Prometheus endpoint for metrics"
  value       = var.enable_prometheus ? "http://prometheus-kube-prometheus-prometheus.${local.observability_namespace}.svc.cluster.local:9090" : null
}

output "kiali_endpoint" {
  description = "Kiali endpoint for service mesh visualization"
  value       = var.enable_kiali ? "http://kiali-server.${local.observability_namespace}.svc.cluster.local:20001" : null
}

# ============================================================================
# Configuration Information
# ============================================================================

output "observability_namespace" {
  description = "Namespace where observability components are deployed"
  value       = local.observability_namespace
}

output "tenant_configurations" {
  description = "Configured tenant information"
  value       = local.tenant_configs
}

# ============================================================================
# SSM Parameters (for integration with other layers)
# ============================================================================

resource "aws_ssm_parameter" "logs_bucket_name" {
  name  = "/${var.project_name}/${var.environment}/${var.region}/observability/logs-bucket-name"
  type  = "String"
  value = module.logs_bucket.bucket_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "traces_bucket_name" {
  name  = "/${var.project_name}/${var.environment}/${var.region}/observability/traces-bucket-name"
  type  = "String"
  value = module.traces_bucket.bucket_id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "tempo_endpoint" {
  name  = "/${var.project_name}/${var.environment}/${var.region}/observability/tempo-endpoint"
  type  = "String"
  value = var.enable_tempo ? "http://tempo.${local.observability_namespace}.svc.cluster.local:3100" : ""
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "prometheus_endpoint" {
  name  = "/${var.project_name}/${var.environment}/${var.region}/observability/prometheus-endpoint"
  type  = "String"
  value = var.enable_prometheus ? "http://prometheus-kube-prometheus-prometheus.${local.observability_namespace}.svc.cluster.local:9090" : ""
  tags  = local.common_tags
}

output "ssm_parameter_names" {
  description = "SSM parameter names for integration with other layers"
  value = {
    logs_bucket_name    = aws_ssm_parameter.logs_bucket_name.name
    traces_bucket_name  = aws_ssm_parameter.traces_bucket_name.name
    tempo_endpoint      = aws_ssm_parameter.tempo_endpoint.name
    prometheus_endpoint = aws_ssm_parameter.prometheus_endpoint.name
  }
}

# ============================================================================
# Summary Information
# ============================================================================

output "observability_summary" {
  description = "Summary of deployed observability components"
  value = {
    region             = var.region
    cluster_name       = var.cluster_name
    namespace          = local.observability_namespace
    fluent_bit_enabled = var.enable_fluent_bit
    tempo_enabled      = var.enable_tempo
    prometheus_enabled = var.enable_prometheus
    kiali_enabled      = var.enable_kiali
    logs_bucket        = module.logs_bucket.bucket_id
    traces_bucket      = module.traces_bucket.bucket_id
    tenant_count       = length(var.tenant_configs)
  }
}
