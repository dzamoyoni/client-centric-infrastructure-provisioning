# ============================================================================
# Layer 01.5: Transit Gateway - Variables
# ============================================================================

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
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-2)."
  }
}

variable "contact_email" {
  description = "Contact email for operational notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.contact_email))
    error_message = "Contact email must be a valid email address."
  }
}

# ============================================================================
# Transit Gateway Configuration
# ============================================================================

variable "transit_gateway_asn" {
  description = "BGP ASN for the Transit Gateway"
  type        = number
  default     = 64512
  
  validation {
    condition     = (var.transit_gateway_asn >= 64512 && var.transit_gateway_asn <= 65534) || (var.transit_gateway_asn >= 4200000000 && var.transit_gateway_asn <= 4294967294)
    error_message = "ASN must be in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "enable_transit_gateway_flow_logs" {
  description = "Enable Transit Gateway flow logs for network monitoring"
  type        = bool
  default     = true
}

variable "transit_gateway_flow_log_retention_days" {
  description = "Number of days to retain Transit Gateway flow logs"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.transit_gateway_flow_log_retention_days)
    error_message = "Flow log retention must be a valid CloudWatch Logs retention period."
  }
}
