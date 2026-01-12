# ============================================================================
# Client VPC Module Variables
# ============================================================================

variable "project_name" {
  description = "Name of the project for resource naming (DEPRECATED - not used in client-centric architecture)"
  type        = string
  default     = ""

  validation {
    condition     = var.project_name == "" || can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "client_name" {
  description = "Name of the client (e.g., est-test-a, est-test-b)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client_name))
    error_message = "Client name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the client VPC - must be unique per client globally"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.)", var.vpc_cidr))
    error_message = "VPC CIDR must be from private IP ranges (10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16)."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use for high availability"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster for subnet tagging"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "database_ports" {
  description = "Database ports to allow in security groups (e.g., PostgreSQL ports)"
  type        = list(number)

  validation {
    condition     = alltrue([for port in var.database_ports : port >= 1024 && port <= 65535])
    error_message = "Database ports must be between 1024 and 65535."
  }
}

variable "custom_ports" {
  description = "Custom application ports to allow in compute security groups"
  type        = list(number)
  default     = []

  validation {
    condition     = alltrue([for port in var.custom_ports : port >= 1024 && port <= 65535])
    error_message = "Custom ports must be between 1024 and 65535."
  }
}

# ============================================================================
# VPC Flow Logs Configuration
# ============================================================================

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for security monitoring"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period for VPC Flow Logs in CloudWatch (days)"
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention days must be a valid CloudWatch Logs retention period."
  }
}
