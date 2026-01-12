# ============================================================================
# Observability Layer Module Variables
# ============================================================================

# ============================================================================
# Core Configuration Variables
# ============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  validation {
    condition     = length(var.project_name) > 0
    error_message = "Project name cannot be empty."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_arn" {
  description = "The OIDC issuer ARN for the EKS cluster"
  type        = string
}

variable "node_group_role_names" {
  description = "List of existing node group IAM role names for EBS CSI policy attachment"
  type        = list(string)
  default     = []
}

variable "enable_gp3_storage" {
  description = "Enable GP3 StorageClass creation (more performant but potentially more expensive)"
  type        = bool
  default     = false
}

# ============================================================================
# Tenant Configuration
# ============================================================================

variable "tenant_configs" {
  description = "List of tenant configurations for multi-tenancy support"
  type = list(object({
    name      = string
    namespace = string
    labels    = map(string)
  }))
  default = []
}

# ============================================================================
# Common Tags and Labels
# ============================================================================

variable "common_tags" {
  description = "Common tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Common labels applied to all Kubernetes resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# S3 Configuration
# ============================================================================

variable "logs_retention_days" {
  description = "Number of days to retain logs in S3"
  type        = number
  default     = 90
  validation {
    condition     = var.logs_retention_days > 0 && var.logs_retention_days <= 365
    error_message = "Logs retention days must be between 1 and 365."
  }
}

variable "traces_retention_days" {
  description = "Number of days to retain traces in S3"
  type        = number
  default     = 90
  validation {
    condition     = var.traces_retention_days > 0 && var.traces_retention_days <= 90
    error_message = "Traces retention days must be between 1 and 90."
  }
}

# ============================================================================
# Enhanced S3 Configuration (New)
# ============================================================================

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "logs_kms_key_id" {
  description = "KMS key ID for logs bucket encryption (empty for AES256)"
  type        = string
  default     = ""
}

variable "traces_kms_key_id" {
  description = "KMS key ID for traces bucket encryption (empty for AES256)"
  type        = string
  default     = ""
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for S3 buckets"
  type        = bool
  default     = false
}

variable "logs_replication_bucket_arn" {
  description = "ARN of destination bucket for logs replication"
  type        = string
  default     = ""
}

variable "traces_replication_bucket_arn" {
  description = "ARN of destination bucket for traces replication"
  type        = string
  default     = ""
}

variable "enable_bucket_monitoring" {
  description = "Enable S3 bucket notifications and monitoring"
  type        = bool
  default     = true
}

variable "logs_notification_topics" {
  description = "SNS topics for logs bucket notifications"
  type = list(object({
    arn           = string
    events        = list(string)
    filter_prefix = optional(string, "")
    filter_suffix = optional(string, "")
  }))
  default = []
}

variable "traces_notification_topics" {
  description = "SNS topics for traces bucket notifications"
  type = list(object({
    arn           = string
    events        = list(string)
    filter_prefix = optional(string, "")
    filter_suffix = optional(string, "")
  }))
  default = []
}

# ============================================================================
# Fluent Bit Configuration
# ============================================================================

variable "enable_fluent_bit" {
  description = "Enable Fluent Bit for log shipping"
  type        = bool
  default     = true
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit Helm chart version"
  type        = string
  default     = "0.21.7"
}

variable "fluent_bit_image_tag" {
  description = "Fluent Bit Docker image tag"
  type        = string
  default     = "2.2.2"
}

variable "fluent_bit_resources" {
  description = "Resource requests and limits for Fluent Bit"
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
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
  }
}

# ============================================================================
# Grafana Tempo Configuration
# ============================================================================

variable "enable_tempo" {
  description = "Enable Grafana Tempo for distributed tracing"
  type        = bool
  default     = true
}

variable "tempo_chart_version" {
  description = "Grafana Tempo Helm chart version"
  type        = string
  default     = "1.7.2"
}

variable "tempo_resources" {
  description = "Resource requests and limits for Tempo"
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
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }
}

# ============================================================================
# Prometheus Configuration
# ============================================================================

variable "enable_prometheus" {
  description = "Enable Prometheus for metrics collection"
  type        = bool
  default     = true
}

variable "prometheus_chart_version" {
  description = "Prometheus Helm chart version"
  type        = string
  default     = "55.5.0"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "10Gi"
}

variable "prometheus_resources" {
  description = "Resource requests and limits for Prometheus"
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
  default = {
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
  }
}

# ============================================================================
# Prometheus Remote Write Configuration
# ============================================================================

variable "prometheus_remote_write_url" {
  description = "Remote write URL for Prometheus (your central Grafana)"
  type        = string
  default     = ""
}

variable "prometheus_remote_write_username" {
  description = "Username for Prometheus remote write authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "prometheus_remote_write_password" {
  description = "Password for Prometheus remote write authentication"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================================================
# Kiali Configuration
# ============================================================================

variable "enable_kiali" {
  description = "Enable Kiali for service mesh visualization"
  type        = bool
  default     = true
}

variable "kiali_chart_version" {
  description = "Kiali Helm chart version"
  type        = string
  default     = "1.78.0"
}

variable "kiali_auth_strategy" {
  description = "Authentication strategy for Kiali"
  type        = string
  default     = "anonymous"
  validation {
    condition     = contains(["anonymous", "token", "openshift"], var.kiali_auth_strategy)
    error_message = "Kiali auth strategy must be one of: anonymous, token, openshift."
  }
}

variable "external_prometheus_url" {
  description = "External Prometheus URL if not using local Prometheus"
  type        = string
  default     = ""
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "create_namespace" {
  description = "Whether to create the observability namespace"
  type        = bool
  default     = false
}

variable "additional_s3_bucket_policies" {
  description = "Additional S3 bucket policies for cross-region access"
  type        = list(string)
  default     = []
}

variable "replication_destination_region" {
  description = "Destination region for S3 cross-region replication"
  type        = string
  default     = ""
}

# ============================================================================
# PRODUCTION-GRADE OBSERVABILITY VARIABLES
# ============================================================================

# ============================================================================
# ALERTING & NOTIFICATION CONFIGURATION
# ============================================================================

variable "enable_alertmanager" {
  description = "Enable AlertManager for production alerting"
  type        = bool
  default     = true
}

variable "alertmanager_storage_size" {
  description = "Storage size for AlertManager"
  type        = string
  default     = "10Gi"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alert notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
}

# ============================================================================
# GRAFANA CONFIGURATION
# ============================================================================

variable "enable_grafana" {
  description = "Enable Grafana for local dashboards and visualization"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana (generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana"
  type        = string
  default     = "10Gi"
}

variable "grafana_temporary_mode" {
  description = "Deploy Grafana in temporary mode (no persistence, faster startup)"
  type        = bool
  default     = true
}

# ============================================================================
# ENHANCED MONITORING & SERVICE DISCOVERY
# ============================================================================

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring features (ServiceMonitors, PrometheusRules)"
  type        = bool
  default     = true
}

variable "enable_postgres_monitoring" {
  description = "Enable PostgreSQL monitoring for client databases"
  type        = bool
  default     = false
}

variable "postgres_endpoints" {
  description = "PostgreSQL endpoints to monitor"
  type = map(object({
    host     = string
    port     = string
    database = string
    client   = string
  }))
  default = {}
}

# ============================================================================
# HIGH AVAILABILITY CONFIGURATION
# ============================================================================

variable "prometheus_replicas" {
  description = "Number of Prometheus replicas for high availability"
  type        = number
  default     = 2
  validation {
    condition     = var.prometheus_replicas >= 1 && var.prometheus_replicas <= 5
    error_message = "Prometheus replicas must be between 1 and 5."
  }
}

variable "enable_prometheus_ha" {
  description = "Enable Prometheus high availability mode"
  type        = bool
  default     = true
}

# ============================================================================
# SECURITY CONFIGURATION
# ============================================================================

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies for observability components"
  type        = bool
  default     = true
}

variable "enable_pod_security_policies" {
  description = "Enable Pod Security Policies for enhanced security"
  type        = bool
  default     = true
}

# ============================================================================
# PERFORMANCE & RESOURCE OPTIMIZATION
# ============================================================================

variable "prometheus_retention" {
  description = "How long to retain Prometheus metrics"
  type        = string
  default     = "30d"
}

variable "prometheus_retention_size" {
  description = "Maximum size of Prometheus storage before oldest data is deleted"
  type        = string
  default     = "25GB"
}

# ============================================================================
# ALERTMANAGER ADDITIONAL CONFIGURATION
# ============================================================================

variable "alertmanager_storage_class" {
  description = "Storage class for AlertManager persistent volume"
  type        = string
  default     = "gp2"
}

variable "alertmanager_replicas" {
  description = "Number of AlertManager replicas for high availability"
  type        = number
  default     = 2
  validation {
    condition     = var.alertmanager_replicas >= 1 && var.alertmanager_replicas <= 5
    error_message = "AlertManager replicas must be between 1 and 5."
  }
}

variable "enable_security_context" {
  description = "Enable security context for pods (runAsNonRoot, etc.)"
  type        = bool
  default     = true
}
