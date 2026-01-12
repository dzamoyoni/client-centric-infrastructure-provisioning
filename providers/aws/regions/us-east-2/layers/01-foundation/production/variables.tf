#  Variables for Foundation Layer - Production
#  Per-Client VPC Architecture

# Project Configuration
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

# Monitoring Configuration
variable "sns_topic_arn" {
  description = "SNS topic ARN for VPN alarms"
  type        = string
  default     = null
}

# ============================================================================
# Per-Client Configuration
# ============================================================================
# Clients are defined in clients.auto.tfvars
# Each client gets a dedicated VPC with unique CIDR from cidr-registry.yaml

variable "clients" {
  description = "Map of client configurations for dynamic per-client VPC provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    # Per-client VPC CIDR - must be globally unique
    network = object({
      vpc_cidr = string  # From cidr-registry.yaml
    })
    
    # Security group configuration
    security = object({
      custom_ports   = list(number)
      database_ports = list(number)
    })
    
    # Optional VPN configuration
    vpn = optional(object({
      enabled             = bool
      customer_gateway_ip = string
      bgp_asn             = number
      amazon_side_asn     = number
      static_routes_only  = bool
      local_network_cidr  = string
      tunnel1_inside_cidr = string
      tunnel2_inside_cidr = string
      description         = string
    }))
    
    # Client metadata for tagging
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
