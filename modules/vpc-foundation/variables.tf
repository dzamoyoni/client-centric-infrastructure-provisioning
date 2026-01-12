# Variables for VPC Foundation Module

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cptwn-eks"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project       = "CPTWN-Multi-Client-EKS"
    ManagedBy     = "Terraform"
    CriticalInfra = "true"
  }
}

# Client subnet configuration
variable "client_configs" {
  description = "Configuration for each client including subnet allocations"
  type = map(object({
    base_cidr_block = string
    enabled         = bool
  }))

  default = {
    ezra = {
      base_cidr_block = "172.16.4.0/22" # 4,094 IPs for Ezra
      enabled         = true
    }
    mtn-ghana = {
      base_cidr_block = "172.16.8.0/22" # 4,094 IPs for MTN Ghana
      enabled         = true
    }
    future-client = {
      base_cidr_block = "172.16.12.0/22" # 4,094 IPs for future client
      enabled         = false            # Reserved for future use
    }
  }
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for security monitoring"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period for VPC Flow Logs in days"
  type        = number
  default     = 30
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for cost optimization"
  type        = bool
  default     = true
}
