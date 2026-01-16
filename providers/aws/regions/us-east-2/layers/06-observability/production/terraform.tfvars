# =============================================================================
# Observability Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State
terraform_state_bucket = "ohio-01-terraform-state-production"
terraform_state_region = "us-east-2"

# Prometheus Configuration
prometheus_retention      = "30d"
prometheus_retention_size = "25GB"

# Loki Configuration
loki_retention_days = 30

# Tempo Configuration
tempo_retention_hours = 336  # 14 days

# Grafana Configuration
grafana_admin_password = "change-me-in-production"
grafana_storage        = "50Gi"

# Alerting
alert_email       = "alerts@example.com"
slack_webhook_url = ""

# Feature Flags
enable_fluent_bit    = true
enable_loki          = true
enable_tempo         = true
enable_node_exporter = true
