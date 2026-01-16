# =============================================================================
# Cluster Services Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State
terraform_state_bucket = "ohio-01-terraform-state-production"
terraform_state_region = "us-east-2"

# Service Enablement
enable_cluster_autoscaler           = true
enable_aws_load_balancer_controller = true
enable_metrics_server               = true
enable_external_dns                 = true  # Enable for automatic DNS management
enable_istio_service_mesh           = true

# Service Versions
cluster_autoscaler_version           = "9.37.0"
aws_load_balancer_controller_version = "1.8.1"
metrics_server_version               = "3.12.1"
external_dns_version                 = "1.14.5"

# Cluster Autoscaler Configuration
cluster_autoscaler_scale_down_enabled              = true
cluster_autoscaler_scale_down_delay_after_add      = "10m"
cluster_autoscaler_scale_down_unneeded_time        = "10m"
cluster_autoscaler_skip_nodes_with_local_storage   = false

# Istio Service Mesh Configuration
istio_version               = "1.27.1"
istio_mesh_id              = "ohio-mesh"
istio_cluster_network      = "ohio-network"
istio_trust_domain         = "cluster.local"

# Ambient Mode
enable_istio_ambient_mode = true

# Ingress Gateway
enable_istio_ingress_gateway            = true
istio_ingress_gateway_replicas          = 2
istio_ingress_gateway_autoscale_enabled = true
istio_ingress_gateway_autoscale_min     = 2
istio_ingress_gateway_autoscale_max     = 5
istio_ingress_gateway_resources = {
  requests = {
    cpu    = "500m"
    memory = "512Mi"
  }
  limits = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}

# Istiod Configuration
istio_istiod_autoscale_enabled = true
istio_istiod_autoscale_min     = 2
istio_istiod_autoscale_max     = 5
istio_istiod_resources = {
  requests = {
    cpu    = "250m"
    memory = "256Mi"
  }
  limits = {
    cpu    = "500m"
    memory = "512Mi"
  }
}

# Application Namespaces
istio_application_namespaces = {}

# Observability
enable_istio_distributed_tracing = true
enable_istio_access_logging      = true
istio_tracing_sampling_rate      = 0.1

# Monitoring
enable_istio_service_monitor  = true
enable_istio_prometheus_rules = true

# Route53 DNS Configuration (NEW - replaces dns_zone_ids)
parent_dns_zone          = "ezra.world"
create_root_placeholder  = true

# Legacy DNS variables (deprecated - zones now auto-created per client)
dns_zone_ids                = []  # No longer needed - auto-managed
external_dns_domain_filters = []  # No longer needed - auto-managed
external_dns_policy         = "upsert-only"

# Additional Tags
additional_tags = {}
