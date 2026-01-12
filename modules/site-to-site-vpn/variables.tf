# Variables for Site-to-Site VPN Module
# Updated for per-client VPC architecture

variable "enabled" {
  description = "Whether to create VPN infrastructure"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Name of the project (DEPRECATED - not used in client-centric architecture)"
  type        = string
  default     = ""
}

variable "client_name" {
  description = "Name of the client (e.g., est-test-a, est-test-b)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client_name))
    error_message = "Client name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the client VPC to attach VPN Gateway"
  type        = string
}

variable "customer_gateway_ip" {
  description = "Public IP address of the customer gateway (on-premises)"
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "Customer gateway IP must be a valid IPv4 address."
  }
}

variable "bgp_asn" {
  description = "BGP ASN for the customer gateway"
  type        = number
  default     = 65000

  validation {
    condition     = var.bgp_asn >= 1 && var.bgp_asn <= 4294967295
    error_message = "BGP ASN must be between 1 and 4294967295."
  }
}

variable "amazon_side_asn" {
  description = "BGP ASN for the Amazon side of the VPN connection"
  type        = number
  default     = 64512

  validation {
    condition     = var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534
    error_message = "Amazon side ASN must be between 64512 and 65534."
  }
}

variable "static_routes_only" {
  description = "Whether to use static routing instead of BGP"
  type        = bool
  default     = true
}

variable "onprem_cidr_blocks" {
  description = "List of on-premises CIDR blocks to route to"
  type        = list(string)
  default     = ["178.162.141.130/32"] # Your specific on-premises IP
}

variable "tunnel1_inside_cidr" {
  description = "CIDR block for tunnel 1 inside network"
  type        = string
  default     = "169.254.10.0/30"
}

variable "tunnel1_preshared_key" {
  description = "Preshared key for tunnel 1"
  type        = string
  default     = null
  sensitive   = true
}

variable "tunnel2_inside_cidr" {
  description = "CIDR block for tunnel 2 inside network"
  type        = string
  default     = "169.254.11.0/30"
}

variable "tunnel2_preshared_key" {
  description = "Preshared key for tunnel 2"
  type        = string
  default     = null
  sensitive   = true
}

variable "client_route_table_ids" {
  description = "List of client's private route table IDs for VPN route propagation (from client-vpc module)"
  type        = list(string)
  default     = []
}

variable "enable_vpn_logging" {
  description = "Enable VPN connection logging"
  type        = bool
  default     = true
}

variable "vpn_log_retention_days" {
  description = "Retention period for VPN logs in days"
  type        = number
  default     = 30
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for VPN alarms"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project       = "ohio-01"
    ManagedBy     = "Terraform"
    CriticalInfra = "true"
  }
}
