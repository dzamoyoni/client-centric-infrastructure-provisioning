# =============================================================================
# Observability Module Outputs
# =============================================================================

# =============================================================================
# Namespace
# =============================================================================

output "namespace" {
  description = "Monitoring namespace name"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

# =============================================================================
# Service Endpoints
# =============================================================================

output "prometheus_url" {
  description = "Prometheus service URL (cluster-internal)"
  value       = "http://${var.client_name}-prometheus-prometheus.${local.namespace}.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Grafana service URL (cluster-internal)"
  value       = "http://${var.client_name}-grafana.${local.namespace}.svc.cluster.local:80"
}

output "alertmanager_url" {
  description = "AlertManager service URL (cluster-internal)"
  value       = "http://${var.client_name}-prometheus-alertmanager.${local.namespace}.svc.cluster.local:9093"
}

output "loki_url" {
  description = "Loki gateway service URL (cluster-internal)"
  value       = var.enable_loki ? "http://${var.client_name}-loki-gateway.${local.namespace}.svc.cluster.local:80" : null
}

output "tempo_url" {
  description = "Tempo service URL (cluster-internal)"
  value       = var.enable_tempo ? "http://${var.client_name}-tempo.${local.namespace}.svc.cluster.local:3100" : null
}

# =============================================================================
# Access Instructions
# =============================================================================

output "grafana_port_forward" {
  description = "kubectl port-forward command for Grafana access"
  value       = "kubectl port-forward -n ${local.namespace} svc/${var.client_name}-grafana 3000:80"
}

output "prometheus_port_forward" {
  description = "kubectl port-forward command for Prometheus access"
  value       = "kubectl port-forward -n ${local.namespace} svc/${var.client_name}-prometheus-prometheus 9090:9090"
}

output "alertmanager_port_forward" {
  description = "kubectl port-forward command for AlertManager access"
  value       = "kubectl port-forward -n ${local.namespace} svc/${var.client_name}-prometheus-alertmanager 9093:9093"
}

# =============================================================================
# IAM Role ARNs
# =============================================================================

output "fluent_bit_role_arn" {
  description = "Fluent Bit IAM role ARN"
  value       = aws_iam_role.fluent_bit.arn
}

output "loki_role_arn" {
  description = "Loki IAM role ARN"
  value       = var.enable_loki ? aws_iam_role.loki[0].arn : null
}

output "tempo_role_arn" {
  description = "Tempo IAM role ARN"
  value       = var.enable_tempo ? aws_iam_role.tempo[0].arn : null
}

# =============================================================================
# Storage Information
# =============================================================================

output "s3_logs_prefix" {
  description = "S3 prefix for logs"
  value       = local.logs_prefix
}

output "s3_traces_prefix" {
  description = "S3 prefix for traces"
  value       = local.traces_prefix
}

output "s3_metrics_prefix" {
  description = "S3 prefix for metrics"
  value       = local.metrics_prefix
}

# =============================================================================
# Component Status
# =============================================================================

output "components_deployed" {
  description = "Status of deployed components"
  value = {
    prometheus    = "deployed"
    grafana       = "deployed"
    alertmanager  = "deployed"
    node_exporter = var.enable_node_exporter ? "deployed" : "disabled"
    loki          = var.enable_loki ? "deployed" : "disabled"
    tempo         = var.enable_tempo ? "deployed" : "disabled"
    fluent_bit    = var.enable_fluent_bit ? "deployed" : "disabled"
  }
}

# =============================================================================
# Configuration Summary
# =============================================================================

output "configuration" {
  description = "Observability stack configuration summary"
  value = {
    client_name           = var.client_name
    client_tier           = var.client_tier
    namespace             = local.namespace
    prometheus_retention  = var.prometheus_retention
    prometheus_replicas   = var.prometheus_replicas
    loki_retention_days   = var.loki_retention_days
    tempo_retention_hours = var.tempo_retention_hours
    grafana_admin_user    = "admin"
  }
  sensitive = false
}
