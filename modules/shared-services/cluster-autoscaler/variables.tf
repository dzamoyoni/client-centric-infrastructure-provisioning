# Variables for Cluster Autoscaler Module

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}


variable "helm_chart_version" {
  description = "Version of the Helm chart"
  type        = string
}

variable "service_account_name" {
  description = "Name of the service account"
  type        = string
}

variable "scale_down_enabled" {
  description = "Enable scale down"
  type        = bool
  default     = true
}

variable "scale_down_delay_after_add" {
  description = "Scale down delay after add"
  type        = string
  default     = "10m"
}

variable "scale_down_unneeded_time" {
  description = "Scale down unneeded time"
  type        = string
  default     = "10m"
}

variable "skip_nodes_with_local_storage" {
  description = "Skip nodes with local storage"
  type        = bool
  default     = false
}

variable "external_irsa_role_arn" {
  description = "External IRSA role ARN. If provided, the module will use this instead of creating its own IRSA role."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "manage_chart_service_account" {
  description = "Whether to manage the service account created by the Helm chart"
  type        = bool
  default     = true
}
