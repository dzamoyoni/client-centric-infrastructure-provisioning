# ============================================================================
# Egress VPC Module - Variables
# ============================================================================

# ============================================================================
# Required Variables
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 64
    error_message = "Project name must be between 1 and 64 characters."
  }
}

variable "region" {
  description = "AWS region"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-2)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the egress VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for the egress VPC"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

# ============================================================================
# High Availability Configuration
# ============================================================================

variable "enable_high_availability" {
  description = "Enable high availability with NAT Gateways in multiple AZs (recommended for production)"
  type        = bool
  default     = false
}

# ============================================================================
# VPC Endpoints
# ============================================================================

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for S3 and DynamoDB (cost optimization)"
  type        = bool
  default     = true
}

# ============================================================================
# Flow Logs
# ============================================================================

variable "enable_flow_logs" {
  description = "Enable VPC flow logs for security monitoring"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention must be a valid CloudWatch Logs retention period."
  }
}
