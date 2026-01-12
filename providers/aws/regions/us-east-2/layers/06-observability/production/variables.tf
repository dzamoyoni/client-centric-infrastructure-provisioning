# ============================================================================
# Observability Layer Variables - US-East-2 Production
# ============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

# ============================================================================
# S3 Configuration
# ============================================================================

variable "logs_retention_days" {
  description = "Number of days to retain logs in S3"
  type        = number
}

variable "traces_retention_days" {
  description = "Number of days to retain traces in S3"
  type        = number
}

variable "tempo_s3_bucket" {
  description = "S3 bucket name for Tempo traces storage"
  type        = string
}

# ============================================================================
# Prometheus Configuration
# ============================================================================

variable "enable_local_prometheus" {
  description = "Enable local Prometheus instance"
  type        = bool
}

variable "prometheus_remote_write_url" {
  description = "Remote write URL for your central on-premises Grafana"
  type        = string
}

variable "prometheus_remote_write_username" {
  description = "Username for Prometheus remote write authentication"
  type        = string
  sensitive   = true
}

variable "prometheus_remote_write_password" {
  description = "Password for Prometheus remote write authentication"
  type        = string
  sensitive   = true
}

# ============================================================================
# Kiali Configuration
# ============================================================================

variable "kiali_auth_strategy" {
  description = "Authentication strategy for Kiali"
  type        = string
}

variable "external_prometheus_url" {
  description = "External Prometheus URL if not using local Prometheus"
  type        = string
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication to us-east-1"
  type        = bool
}

variable "clients" {
  description = "Map of client configurations for dynamic provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    network = object({
      cidr_offset = number
    })
    
    eks = object({
      enabled         = bool
      instance_types  = list(string)
      min_size        = number
      max_size        = number
      desired_size    = number
      disk_size       = number
      capacity_type   = string
    })
    
    compute = object({
      analytics_enabled = bool
      instance_type     = string
      root_volume_size  = number
      data_volume_size  = number
    })
    
    storage = object({
      enable_dedicated_buckets = bool
      backup_retention_days    = number
    })
    
    security = object({
      custom_ports   = list(number)
      database_ports = list(number)
    })
    
    metadata = object({
      full_name       = string
      industry        = string
      contact_email   = string
      compliance      = list(string)
      cost_center     = string
      business_unit   = string
    })
  }))
}

variable "additional_tenant_namespaces" {
  description = "Additional tenant namespaces to monitor (beyond client namespaces)"
  type        = list(string)
}

# ============================================================================
# Production Enhancement Variables
# ============================================================================

variable "grafana_admin_password" {
  description = "Admin password for Grafana (auto-generated if empty)"
  type        = string
  sensitive   = true
}

variable "prometheus_replicas" {
  description = "Number of Prometheus replicas for HA"
  type        = number
}

variable "enable_prometheus_ha" {
  description = "Enable Prometheus high availability"
  type        = bool
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
}

variable "prometheus_retention_size" {
  description = "Prometheus data retention size"
  type        = string
}

variable "enable_network_policies" {
  description = "Enable network policies for security"
  type        = bool
}

variable "enable_pod_security_policies" {
  description = "Enable pod security policies"
  type        = bool
}

# ============================================================================
# ALERTMANAGER CONFIGURATION
# ============================================================================

variable "alertmanager_storage_class" {
  description = "Storage class for AlertManager persistent volume"
  type        = string
  validation {
    condition     = contains(["gp2", "gp3"], var.alertmanager_storage_class)
    error_message = "AlertManager storage class must be either 'gp2' or 'gp3'."
  }
}

variable "alertmanager_replicas" {
  description = "Number of AlertManager replicas for high availability"
  type        = number
}

variable "enable_security_context" {
  description = "Enable security context for pods (runAsNonRoot, etc.)"
  type        = bool
}

# ============================================================================
# JAEGER DISTRIBUTED TRACING CONFIGURATION
# ============================================================================

variable "enable_jaeger" {
  description = "Enable Jaeger for distributed tracing (optimized for Java applications)"
  type        = bool
}

variable "jaeger_storage_type" {
  description = "Jaeger storage backend type (cassandra, elasticsearch, memory)"
  type        = string
  validation {
    condition     = contains(["cassandra", "elasticsearch", "memory"], var.jaeger_storage_type)
    error_message = "Jaeger storage type must be one of: cassandra, elasticsearch, memory."
  }
}

variable "jaeger_s3_export_enabled" {
  description = "Enable S3 export for Jaeger traces (via Tempo)"
  type        = bool
}

variable "jaeger_resources" {
  description = "Resource requests and limits for Jaeger components"
  type = object({
    collector = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
    query = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
  })
}

# ============================================================================
# OPENTELEMETRY CONFIGURATION
# ============================================================================

variable "enable_otel_collector" {
  description = "Enable OpenTelemetry Collector for modern observability data collection"
  type        = bool
}

variable "otel_collector_mode" {
  description = "OpenTelemetry Collector deployment mode (daemonset, deployment, sidecar)"
  type        = string
  validation {
    condition     = contains(["daemonset", "deployment", "sidecar"], var.otel_collector_mode)
    error_message = "OTEL collector mode must be one of: daemonset, deployment, sidecar."
  }
}

variable "otel_java_instrumentation_enabled" {
  description = "Enable auto-instrumentation for Java applications"
  type        = bool
}

variable "otel_collector_resources" {
  description = "Resource requests and limits for OpenTelemetry Collector"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
}

# ============================================================================
# S3 EXPORT AND STORAGE CONFIGURATION
# ============================================================================

variable "s3_export_enabled" {
  description = "Enable S3 export for all observability data (logs, metrics, traces)"
  type        = bool
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
}

variable "s3_transition_to_ia_days" {
  description = "Days after which to transition S3 objects to Infrequent Access"
  type        = number
}

variable "s3_transition_to_glacier_days" {
  description = "Days after which to transition S3 objects to Glacier"
  type        = number
}

variable "s3_expiration_days" {
  description = "Days after which to delete S3 objects (0 = never delete)"
  type        = number
}

variable "disable_local_storage" {
  description = "Disable local storage on nodes (force S3-only storage)"
  type        = bool
}

# ============================================================================
# TERRAFORM STATE CONFIGURATION
# ============================================================================

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform remote state"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region where Terraform state bucket is located"
  type        = string
}

# ============================================================================
# ALERTING CONFIGURATION
# ============================================================================

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}
