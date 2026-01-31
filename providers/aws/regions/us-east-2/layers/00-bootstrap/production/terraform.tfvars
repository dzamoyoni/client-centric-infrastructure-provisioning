# ============================================================================
# Layer 00: Bootstrap - Terraform Configuration
# ============================================================================
# Purpose: Configuration values for bootstrap infrastructure
# ============================================================================

# Core configuration
organization_name = "myorg"  # Change to your organization name
environment       = "production"
region            = "us-east-2"
contact_email     = "platform-team@example.com"  # Change to your team email

# Observability retention configuration (optimized for cost)
logs_retention_days    = 180  # Logs: 180 days (long-term troubleshooting)
metrics_retention_days = 14   # Metrics: 14 days (Prometheus already aggregates)
traces_retention_days  = 7    # Traces: 7 days (high volume, short-term debugging)

# Note: clients variable is defined in clients.auto.tfvars
