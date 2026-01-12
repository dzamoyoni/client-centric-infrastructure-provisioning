# ============================================================================
# Unified Foundation Layer Module Variables
# ============================================================================
# Supports both IMPORT mode (existing infrastructure) and CREATE mode (new regions)
# ============================================================================

# ============================================================================
# Mode Selection
# ============================================================================

variable "import_mode" {
  description = "Explicit mode selection: true=import existing, false=create new, null=auto-detect"
  type        = bool
  default     = null
}

# ============================================================================
# General Configuration
# ============================================================================

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
}

variable "vpc_name" {
  description = "Name for the VPC and related resources"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource tagging)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources are located"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

# ============================================================================
# IMPORT MODE: Existing Infrastructure Configuration
# ============================================================================

variable "existing_vpc_id" {
  description = "[IMPORT MODE] ID of your existing VPC"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "[IMPORT MODE] List of your existing private subnet IDs"
  type        = list(string)
  default     = []
}

variable "existing_public_subnet_ids" {
  description = "[IMPORT MODE] List of your existing public subnet IDs"
  type        = list(string)
  default     = []
}

variable "existing_igw_id" {
  description = "[IMPORT MODE] ID of your existing Internet Gateway"
  type        = string
  default     = ""
}

variable "existing_nat_gateway_ids" {
  description = "[IMPORT MODE] List of your existing NAT Gateway IDs"
  type        = list(string)
  default     = []
}

variable "existing_vpn_gateway_id" {
  description = "[IMPORT MODE] ID of your existing VPN Gateway (if any)"
  type        = string
  default     = ""
}

variable "existing_eks_cluster_sg_id" {
  description = "[IMPORT MODE] ID of your existing EKS cluster security group"
  type        = string
  default     = ""
}

variable "existing_database_sg_id" {
  description = "[IMPORT MODE] ID of your existing database security group"
  type        = string
  default     = ""
}

variable "existing_alb_sg_id" {
  description = "[IMPORT MODE] ID of your existing ALB security group"
  type        = string
  default     = ""
}

# ============================================================================
# CREATE MODE: New Infrastructure Configuration
# ============================================================================

variable "vpc_cidr" {
  description = "[CREATE MODE] CIDR block for the VPC"
  type        = string
  default     = ""
  validation {
    condition     = var.vpc_cidr == "" || can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block or empty for import mode."
  }
}

variable "private_subnets" {
  description = "[CREATE MODE] List of private subnet CIDR blocks"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "[CREATE MODE] List of public subnet CIDR blocks"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "[CREATE MODE] Enable NAT Gateway for outbound internet access"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "[CREATE MODE] Use single NAT Gateway for cost optimization"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "[CREATE MODE] Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "[CREATE MODE] Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_flow_log" {
  description = "[CREATE MODE] Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "flow_log_destination_type" {
  description = "[CREATE MODE] Type of flow log destination"
  type        = string
  default     = "cloud-watch-logs"
  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_log_destination_type)
    error_message = "Flow log destination type must be either 'cloud-watch-logs' or 's3'."
  }
}

variable "enable_vpn" {
  description = "[CREATE MODE] Enable VPN connections for client access"
  type        = bool
  default     = false
}

variable "vpn_config" {
  description = "[CREATE MODE] VPN configuration for client connections"
  type = object({
    customer_gateway_ip   = optional(string, "")
    client_cidr           = optional(string, "")
    bgp_asn               = optional(number, 65000)
    secondary_gateway_ip  = optional(string)
    secondary_client_cidr = optional(string)
    secondary_bgp_asn     = optional(number, 65000)
  })
  default = {}
}

# ============================================================================
# Security Group Configuration
# ============================================================================

variable "create_security_groups" {
  description = "Whether to create new security groups (false = use existing in import mode)"
  type        = bool
  default     = false
}

# ============================================================================
# Tagging Configuration
# ============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Layer     = "foundation"
  }
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "enable_vpc_endpoints" {
  description = "[CREATE MODE] Enable VPC endpoints for AWS services"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks to allow in security groups"
  type        = list(string)
  default     = []
}
