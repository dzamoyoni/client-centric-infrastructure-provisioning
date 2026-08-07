# ============================================================================
# Transit Gateway Module - Variables
# ============================================================================

# ============================================================================
# Required Variables
# ============================================================================

variable "name" {
  description = "Name of the Transit Gateway"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 255
    error_message = "Transit Gateway name must be between 1 and 255 characters."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

# ============================================================================
# Transit Gateway Configuration
# ============================================================================

variable "description" {
  description = "Description of the Transit Gateway"
  type        = string
  default     = "Centralized routing hub for multi-VPC architecture"
}

variable "amazon_side_asn" {
  description = "Private Autonomous System Number (ASN) for the Transit Gateway"
  type        = number
  default     = 64512

  validation {
    condition     = (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) || (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    error_message = "ASN must be in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "default_route_table_association" {
  description = "Whether resource attachments are automatically associated with the default association route table"
  type        = bool
  default     = false
}

variable "default_route_table_propagation" {
  description = "Whether resource attachments automatically propagate routes to the default propagation route table"
  type        = bool
  default     = false
}

variable "dns_support" {
  description = "Whether DNS support is enabled"
  type        = bool
  default     = true
}

variable "vpn_ecmp_support" {
  description = "Whether VPN Equal Cost Multipath Protocol support is enabled"
  type        = bool
  default     = true
}

variable "auto_accept_shared_attachments" {
  description = "Whether resource attachment requests are automatically accepted"
  type        = bool
  default     = false
}

# ============================================================================
# VPC Attachments
# ============================================================================

variable "vpc_attachments" {
  description = "Map of VPC attachments to create"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)

    # Optional settings
    dns_support                                     = optional(bool, true)
    ipv6_support                                    = optional(bool, false)
    appliance_mode_support                          = optional(bool, false)
    transit_gateway_default_route_table_association = optional(bool, true)
    transit_gateway_default_route_table_propagation = optional(bool, true)
    tags                                            = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.vpc_attachments : length(v.subnet_ids) > 0])
    error_message = "Each VPC attachment must have at least one subnet."
  }
}

# ============================================================================
# Route Tables
# ============================================================================

variable "route_tables" {
  description = "Map of Transit Gateway route tables to create"
  type = map(object({
    description = optional(string, "Transit Gateway Route Table")
    tags        = optional(map(string), {})
  }))
  default = {}
}

variable "route_table_associations" {
  description = "Map of route table associations"
  type = map(object({
    vpc_attachment_key = string
    route_table_key    = string
  }))
  default = {}
}

variable "route_table_propagations" {
  description = "Map of route table propagations"
  type = map(object({
    vpc_attachment_key = string
    route_table_key    = string
  }))
  default = {}
}

# ============================================================================
# Static Routes
# ============================================================================

variable "static_routes" {
  description = "Map of static routes to create in Transit Gateway route tables"
  type = map(object({
    destination_cidr_block = string
    route_table_key        = string
    vpc_attachment_key     = optional(string)
    blackhole              = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.static_routes :
      (v.vpc_attachment_key != null && !v.blackhole) || (v.vpc_attachment_key == null && v.blackhole)
    ])
    error_message = "Each route must have either vpc_attachment_key OR blackhole=true, not both."
  }
}

# ============================================================================
# Cross-Account Sharing
# ============================================================================

variable "enable_cross_account_sharing" {
  description = "Enable sharing of Transit Gateway with other AWS accounts"
  type        = bool
  default     = false
}

variable "shared_account_ids" {
  description = "List of AWS account IDs to share the Transit Gateway with"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.shared_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All account IDs must be 12-digit numbers."
  }
}

variable "allow_external_principals" {
  description = "Allow sharing with accounts outside your AWS Organization"
  type        = bool
  default     = false
}

# ============================================================================
# Flow Logs
# ============================================================================

variable "enable_flow_logs" {
  description = "Enable Transit Gateway flow logs for network monitoring"
  type        = bool
  default     = false
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
