# ============================================================================
# Foundation Layer - Variables
# ============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for VPN alarms"
  type        = string
  default     = null
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID (set to null during initial foundation bootstrap)"
  type        = string
  default     = null
}

variable "clients" {
  description = "Map of client configurations for dynamic per-client VPC provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    network = object({
      vpc_cidr = string
    })
    
    security = object({
      custom_ports   = list(number)
      database_ports = list(number)
    })
    
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
    
    metadata = object({
      full_name     = string
      industry      = string
      contact_email = string
      compliance    = list(string)
      cost_center   = string
      business_unit = string
    })
  }))
  
  default = {}
}