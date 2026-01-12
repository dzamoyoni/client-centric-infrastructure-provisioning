# Variables for Shared Services Module

variable "project_name" {
  description = "Name of the project (DEPRECATED - not used in client-centric architecture)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "URL of the OIDC issuer"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable metrics server"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable external DNS"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_version" {
  description = "Version of cluster autoscaler"
  type        = string
  default     = "9.37.0"
}

variable "aws_load_balancer_controller_version" {
  description = "Version of AWS Load Balancer Controller"
  type        = string
  default     = "1.8.1"
}

variable "metrics_server_version" {
  description = "Version of metrics server"
  type        = string
  default     = "3.12.1"
}

variable "dns_zone_ids" {
  description = "DNS zone IDs"
  type        = list(string)
  default     = []
}

variable "cluster_autoscaler_scale_down_enabled" {
  description = "Enable scale down for cluster autoscaler"
  type        = bool
  default     = true
}

variable "cluster_autoscaler_scale_down_delay_after_add" {
  description = "Scale down delay after add"
  type        = string
  default     = "10m"
}

variable "cluster_autoscaler_scale_down_unneeded_time" {
  description = "Scale down unneeded time"
  type        = string
  default     = "10m"
}

variable "cluster_autoscaler_skip_nodes_with_local_storage" {
  description = "Skip nodes with local storage"
  type        = bool
  default     = false
}

# 🔐 EXTERNAL IRSA ROLE ARNs (Optional)
# Use these to integrate with standalone IRSA modules for enhanced permissions

variable "external_alb_controller_irsa_role_arn" {
  description = "External AWS Load Balancer Controller IRSA role ARN. If provided, the module will use this instead of creating its own IRSA role."
  type        = string
  default     = null
  validation {
    condition     = var.external_alb_controller_irsa_role_arn == null || can(regex("^arn:aws[a-z0-9-]*:iam::", var.external_alb_controller_irsa_role_arn))
    error_message = "External ALB controller IRSA role ARN must be a valid IAM role ARN."
  }
}

variable "external_cluster_autoscaler_irsa_role_arn" {
  description = "External Cluster Autoscaler IRSA role ARN. If provided, the module will use this instead of creating its own IRSA role."
  type        = string
  default     = null
  validation {
    condition     = var.external_cluster_autoscaler_irsa_role_arn == null || can(regex("^arn:aws[a-z0-9-]*:iam::", var.external_cluster_autoscaler_irsa_role_arn))
    error_message = "External cluster autoscaler IRSA role ARN must be a valid IAM role ARN."
  }
}

variable "external_external_dns_irsa_role_arn" {
  description = "External External DNS IRSA role ARN. If provided, the module will use this instead of creating its own IRSA role."
  type        = string
  default     = null
  validation {
    condition     = var.external_external_dns_irsa_role_arn == null || can(regex("^arn:aws[a-z0-9-]*:iam::", var.external_external_dns_irsa_role_arn))
    error_message = "External DNS IRSA role ARN must be a valid IAM role ARN."
  }
}

# 🌐 EXTERNAL DNS Configuration
variable "external_dns_version" {
  description = "Version of External DNS Helm chart"
  type        = string
  default     = "1.14.5"
}

variable "external_dns_domain_filters" {
  description = "List of domain filters for External DNS"
  type        = list(string)
  default     = []
}

variable "external_dns_policy" {
  description = "External DNS policy (sync or upsert-only)"
  type        = string
  default     = "upsert-only"
  validation {
    condition     = contains(["sync", "upsert-only"], var.external_dns_policy)
    error_message = "External DNS policy must be either 'sync' or 'upsert-only'."
  }
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
