# =============================================================================
# Variables: Standalone Compute Layer - Analytics Instances
# =============================================================================

# =============================================================================
# Core Configuration Variables
# =============================================================================

variable "region" {
  description = "AWS region for resource deployment"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
}

variable "project_name" {
  description = "Name of the project for resource identification and tagging"
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state storage"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region where Terraform state bucket is located"
  type        = string
}

# =============================================================================
# Dynamic Client Configuration
# ============================================================================= 
# Clients are defined in ../../../clients.auto.tfvars

variable "clients" {
  description = "Map of client configurations for dynamic provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    network = object({
      cidr_offset = number
    })
    
    eks = object({
      enabled        = bool
      instance_types = list(string)
      min_size       = number
      max_size       = number
      desired_size   = number
      disk_size      = number
      capacity_type  = string
    })
    
    compute = object({
      analytics_enabled = bool
      instance_type     = string
      root_volume_size  = number
      data_volume_size  = number
    })
    
    storage = object({
      enable_dedicated_buckets = bool
      backup_retention_days    = number
    })
    
    security = object({
      custom_ports   = list(number)
      database_ports = list(number)
    })
    
    metadata = object({
      full_name      = string
      industry       = string
      contact_email  = string
      compliance     = list(string)
      cost_center    = string
      business_unit  = string
    })
  }))
  
  default = {}
}

variable "regional_network" {
  description = "Regional network configuration"
  type = object({
    vpc_cidr              = string
    client_cidr_base      = string
    client_cidr_increment = number
  })
  
}

