# =============================================================================
# Client Identification
# =============================================================================

variable "client_name" {
  description = "Client name (used for namespace, resources naming)"
  type        = string
}

variable "client_tier" {
  description = "Client tier (premium, standard) - determines resource allocation"
  type        = string
  validation {
    condition     = contains(["premium", "standard"], var.client_tier)
    error_message = "Client tier must be either 'premium' or 'standard'."
  }
}

variable "client_code" {
  description = "Client code for identification"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = ""
}

variable "business_unit" {
  description = "Business unit for organizational tagging"
  type        = string
  default     = ""
}

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64 encoded)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (without https://)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming (DEPRECATED - not used in client-centric architecture)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment (production, staging, dev)"
  type        = string
}

# =============================================================================
# S3 Storage Configuration
# =============================================================================

variable "shared_logs_bucket" {
  description = "Shared S3 bucket name for logs (client-specific prefixes used)"
  type        = string
}

variable "shared_logs_bucket_arn" {
  description = "Shared S3 bucket ARN for logs"
  type        = string
}

variable "shared_traces_bucket" {
  description = "Shared S3 bucket name for traces (client-specific prefixes used)"
  type        = string
}

variable "shared_traces_bucket_arn" {
  description = "Shared S3 bucket ARN for traces"
  type        = string
}

variable "shared_metrics_bucket" {
  description = "Shared S3 bucket name for metrics (client-specific prefixes used)"
  type        = string
}

variable "shared_metrics_bucket_arn" {
  description = "Shared S3 bucket ARN for metrics"
  type        = string
}

# =============================================================================
# Prometheus Configuration
# =============================================================================

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "prometheus_retention_size" {
  description = "Prometheus data retention size"
  type        = string
  default     = "40GB"
}

variable "prometheus_storage" {
  description = "Prometheus persistent storage size"
  type        = string
  default     = "50Gi"
}

variable "prometheus_replicas" {
  description = "Number of Prometheus replicas (1 for standard, 2 for premium)"
  type        = number
  default     = 1
}

variable "prometheus_remote_write_url" {
  description = "Remote write URL for Prometheus (optional)"
  type        = string
  default     = ""
}

# =============================================================================
# Grafana Configuration
# =============================================================================

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_storage" {
  description = "Grafana persistent storage size"
  type        = string
  default     = "20Gi"
}

# =============================================================================
# Loki Configuration
# =============================================================================

variable "loki_retention_days" {
  description = "Loki log retention in days"
  type        = number
  default     = 7
}

# =============================================================================
# Tempo Configuration
# =============================================================================

variable "tempo_retention_hours" {
  description = "Tempo trace retention in hours"
  type        = number
  default     = 168  # 7 days
}

# =============================================================================
# AlertManager Configuration
# =============================================================================

variable "alertmanager_replicas" {
  description = "Number of AlertManager replicas"
  type        = number
  default     = 1
}

variable "alert_email" {
  description = "Email address for alerts (optional)"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Feature Flags
# =============================================================================

variable "enable_fluent_bit" {
  description = "Enable Fluent Bit log collection DaemonSet"
  type        = bool
  default     = true
}

variable "enable_loki" {
  description = "Enable Loki log aggregation"
  type        = bool
  default     = true
}

variable "enable_tempo" {
  description = "Enable Tempo distributed tracing"
  type        = bool
  default     = true
}

variable "enable_node_exporter" {
  description = "Enable Node Exporter DaemonSet"
  type        = bool
  default     = true
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Additional tags for AWS resources"
  type        = map(string)
  default     = {}
}
