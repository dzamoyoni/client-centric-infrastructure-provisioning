# ============================================================================
# Observability Layer Outputs - Per-Client Architecture
# ============================================================================

output "client_observability_stacks" {
  description = "Per-client observability stack information"
  value = {
    for client in keys(local.enabled_clients) : client => {
      namespace               = module.client_observability[client].namespace
      prometheus_url          = module.client_observability[client].prometheus_url
      grafana_url             = module.client_observability[client].grafana_url
      alertmanager_url        = module.client_observability[client].alertmanager_url
      loki_url                = module.client_observability[client].loki_url
      tempo_url               = module.client_observability[client].tempo_url
      grafana_port_forward    = module.client_observability[client].grafana_port_forward
      prometheus_port_forward = module.client_observability[client].prometheus_port_forward
      components_deployed     = module.client_observability[client].components_deployed
    }
  }
}

output "observability_summary" {
  description = "Observability architecture summary"
  value = {
    total_clients = length(local.enabled_clients)
    architecture  = "Per-Client Complete Isolation"
    
    components_per_client = {
      metrics        = "Prometheus (${var.prometheus_retention} retention)"
      alerting       = "AlertManager with email/Slack"
      visualization  = "Grafana with pre-configured dashboards"
      logs           = "Loki with S3 backend"
      traces         = "Tempo with multi-protocol support"
      log_collection = "Fluent Bit DaemonSet"
    }
    
    storage_backend = "AWS S3 with client-specific prefixes"
    isolation_level = "Complete - separate namespace per client"
    network_scope   = "client-vpc-isolated"
  }
}

output "s3_buckets" {
  description = "Shared S3 buckets for observability data storage"
  value = {
    logs    = data.aws_s3_bucket.logs.id
    traces  = data.aws_s3_bucket.traces.id
    metrics = data.aws_s3_bucket.metrics.id
  }
}

output "client_access_instructions" {
  description = "Instructions for accessing client observability stacks"
  value = {
    for client in keys(local.enabled_clients) : client => {
      grafana_access = "kubectl port-forward -n ${client}-monitoring svc/${client}-grafana 3000:80"
      prometheus_access = "kubectl port-forward -n ${client}-monitoring svc/${client}-prometheus 9090:9090"
      grafana_credentials = "admin / <grafana_admin_password>"
    }
  }
}
