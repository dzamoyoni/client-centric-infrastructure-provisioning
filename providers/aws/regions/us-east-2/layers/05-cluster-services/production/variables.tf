# Shared Services Layer Variables
# Configuration variables for Kubernetes shared services deployment

# CORE PROJECT CONFIGURATION
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
}

variable "region" {
  description = "AWS region where resources will be created"
  type        = string
}

# TERRAFORM STATE CONFIGURATION
variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform remote state"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region where Terraform state bucket is located"
  type        = string
}

# SHARED SERVICES CONFIGURATION
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler deployment"
  type        = bool
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller deployment"
  type        = bool
}

variable "enable_metrics_server" {
  description = "Enable metrics server deployment"
  type        = bool
}

variable "enable_external_dns" {
  description = "Enable external DNS controller deployment"
  type        = bool
}

# SERVICE VERSIONS
variable "cluster_autoscaler_version" {
  description = "Version of cluster autoscaler Helm chart"
  type        = string
}

variable "aws_load_balancer_controller_version" {
  description = "Version of AWS Load Balancer Controller Helm chart"
  type        = string
}

variable "metrics_server_version" {
  description = "Version of metrics server Helm chart"
  type        = string
}

# DNS CONFIGURATION
variable "dns_zone_ids" {
  description = "List of Route 53 hosted zone IDs for external DNS (deprecated - now managed per-client)"
  type        = list(string)
}

variable "external_dns_domain_filters" {
  description = "Domain filters for external DNS (deprecated - now managed per-client)"
  type        = list(string)
}

variable "external_dns_policy" {
  description = "External DNS policy (sync or upsert-only)"
  type        = string
  
  validation {
    condition     = contains(["sync", "upsert-only"], var.external_dns_policy)
    error_message = "External DNS policy must be either 'sync' or 'upsert-only'."
  }
}

variable "external_dns_version" {
  description = "Version of External DNS Helm chart"
  type        = string
}

# CLUSTER AUTOSCALER CONFIGURATION
variable "cluster_autoscaler_scale_down_enabled" {
  description = "Enable scale down for cluster autoscaler"
  type        = bool
}

variable "cluster_autoscaler_scale_down_delay_after_add" {
  description = "How long after scale up that scale down evaluation resumes"
  type        = string
}

variable "cluster_autoscaler_scale_down_unneeded_time" {
  description = "How long a node should be unneeded before it is eligible for scale down"
  type        = string
}

variable "cluster_autoscaler_skip_nodes_with_local_storage" {
  description = "Skip nodes with local storage for scale down"
  type        = bool
}

# ADDITIONAL TAGS
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
}

# =============================================================================
# ISTIO SERVICE MESH CONFIGURATION
# =============================================================================

variable "enable_istio_service_mesh" {
  description = "Enable Istio service mesh deployment"
  type        = bool
}

variable "istio_version" {
  description = "Version of Istio to deploy"
  type        = string
}

variable "istio_mesh_id" {
  description = "Mesh ID for Istio"
  type        = string
}

variable "istio_cluster_network" {
  description = "Cluster network name for Istio"
  type        = string
}

variable "istio_trust_domain" {
  description = "Trust domain for Istio"
  type        = string
}

# Ambient Mode Configuration
variable "enable_istio_ambient_mode" {
  description = "Enable Istio ambient mode"
  type        = bool
}

# Ingress Gateway Configuration
variable "enable_istio_ingress_gateway" {
  description = "Enable Istio ingress gateway"
  type        = bool
}

variable "istio_ingress_gateway_replicas" {
  description = "Number of replicas for ingress gateway"
  type        = number
}

variable "istio_ingress_gateway_resources" {
  description = "Resource configuration for ingress gateway"
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

variable "istio_ingress_gateway_autoscale_enabled" {
  description = "Enable autoscaling for ingress gateway"
  type        = bool
}

variable "istio_ingress_gateway_autoscale_min" {
  description = "Minimum replicas for ingress gateway autoscaling"
  type        = number
}

variable "istio_ingress_gateway_autoscale_max" {
  description = "Maximum replicas for ingress gateway autoscaling"
  type        = number
}

# Istiod Configuration
variable "istio_istiod_resources" {
  description = "Resource configuration for istiod"
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

variable "istio_istiod_autoscale_enabled" {
  description = "Enable autoscaling for istiod"
  type        = bool
}

variable "istio_istiod_autoscale_min" {
  description = "Minimum replicas for istiod autoscaling"
  type        = number
}

variable "istio_istiod_autoscale_max" {
  description = "Maximum replicas for istiod autoscaling"
  type        = number
}

# Application Namespace Configuration - Multi-Client
variable "istio_application_namespaces" {
  description = "Configuration for application namespaces with different dataplane modes"
  type = map(object({
    dataplane_mode = string # "ambient" or "sidecar"
    client         = optional(string)
    tenant         = optional(string)
  }))
}

# Observability Integration with Layer 03.5
variable "enable_istio_distributed_tracing" {
  description = "Enable distributed tracing integration with existing Tempo"
  type        = bool
}

variable "enable_istio_access_logging" {
  description = "Enable access logging integration with existing Fluent Bit"
  type        = bool
}

variable "istio_tracing_sampling_rate" {
  description = "Tracing sampling rate for production (0.0 to 1.0)"
  type        = number
}

# Monitoring Integration
variable "enable_istio_service_monitor" {
  description = "Enable ServiceMonitor for Prometheus integration"
  type        = bool
}

variable "enable_istio_prometheus_rules" {
  description = "Enable PrometheusRules for Istio alerting"
  type        = bool
}

# =============================================================================
# PER-CLIENT CONFIGURATION
# =============================================================================

variable "clients" {
  description = "Map of client configurations"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    eks = object({
      enabled         = bool
      instance_types  = list(string)
      min_size        = number
      max_size        = number
      desired_size    = number
      disk_size       = number
      capacity_type   = string
    })
    
    metadata = object({
      full_name     = string
      industry      = string
      contact_email = string
      compliance    = list(string)
      cost_center   = string
      business_unit = string
    })
  }))
  
  default = {}
}

# =============================================================================
# ROUTE53 DNS CONFIGURATION - Per-Client Zones
# =============================================================================

variable "parent_dns_zone" {
  description = "Parent DNS zone (e.g., ezra.world) - must already exist in Route53"
  type        = string
  default     = "ezra.world"
}

variable "create_root_placeholder" {
  description = "Create placeholder TXT records in client zones"
  type        = bool
  default     = true
}
