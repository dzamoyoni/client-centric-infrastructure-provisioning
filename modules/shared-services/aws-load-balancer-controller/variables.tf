# Variables for AWS Load Balancer Controller

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

variable "vpc_id" {
  description = "VPC ID"
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
