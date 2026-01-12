#  Platform Layer Variables - Production
# Per-Client EKS Clusters - Each client gets dedicated cluster in their VPC

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

#  Terraform State Configuration
variable "terraform_state_bucket" {
  description = "S3 bucket for terraform state"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region for terraform state bucket"
  type        = string
}

# EKS Cluster Configuration
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
}

#  EKS Access Configuration
variable "enable_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
}

variable "management_cidr_blocks" {
  description = "CIDR blocks allowed to access EKS API endpoint"
  type        = list(string)
}

# ============================================================================
# Per-Client EKS Configuration
# ============================================================================
# Clients are defined in clients.auto.tfvars
# Each enabled client with eks.enabled = true gets a dedicated EKS cluster

variable "clients" {
  description = "Map of client configurations for per-client EKS cluster provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    # EKS node group configuration
    eks = object({
      enabled        = bool
      instance_types = list(string)
      min_size       = number
      max_size       = number
      desired_size   = number
      disk_size      = number
      capacity_type  = string
    })
    
    # Client metadata
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
