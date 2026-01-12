# =============================================================================
# Per-Client Observability Module
# =============================================================================
# Deploys complete observability stack for a single client in their dedicated
# EKS cluster with complete isolation.
# =============================================================================

# Providers configured by calling layer
# Note: This module expects kubernetes and helm providers to be configured
# by the calling layer with the appropriate cluster context

# Local variables
locals {
  namespace = "${var.client_name}-monitoring"
  
  # Common labels for all resources
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "observability-stack"
    "client"                       = var.client_name
    "tier"                         = var.client_tier
    "environment"                  = var.environment
  }
  
  # IAM role names
  fluent_bit_role_name = "${var.project_name}-${var.client_name}-fluent-bit"
  loki_role_name       = "${var.project_name}-${var.client_name}-loki"
  tempo_role_name      = "${var.project_name}-${var.client_name}-tempo"
  
  # S3 prefixes for client isolation
  logs_prefix   = "clients/${var.client_name}/logs/"
  traces_prefix = "clients/${var.client_name}/traces/"
  metrics_prefix = "clients/${var.client_name}/metrics/"
}
