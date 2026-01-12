# Variables for Client Subnet Isolation Module

variable "enabled" {
  description = "Whether to create client subnets"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "client_name" {
  description = "Name of the client (ezra, mtn-ghana, etc.)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client_name))
    error_message = "Client name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where subnets will be created"
  type        = string
}

variable "client_cidr_block" {
  description = "CIDR block allocated to this client (/22 = 4,094 IPs)"
  type        = string

  validation {
    condition     = can(cidrhost(var.client_cidr_block, 0))
    error_message = "Client CIDR block must be a valid IPv4 CIDR block."
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

variable "nat_gateway_ids" {
  description = "List of NAT Gateway IDs for routing"
  type        = list(string)
}

variable "vpn_gateway_id" {
  description = "ID of the VPN Gateway for on-premises connectivity"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster for subnet tagging"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project       = "Multi-Client-EKS"
    ManagedBy     = "Terraform"
    CriticalInfra = "true"
  }
}

variable "management_cidr_blocks" {
  description = "CIDR blocks for management access (VPN, bastion, etc.)"
  type        = list(string)
  default     = ["10.0.0.0/8"] # Default for on-premises networks
}

variable "onprem_cidr_blocks" {
  description = "On-premises CIDR blocks for VPN routing"
  type        = list(string)
  default     = []
}

variable "custom_ports" {
  description = "Custom application ports to allow in security groups"
  type        = list(number)
  default     = [8080, 9000, 3000] # Common application ports
}

variable "database_ports" {
  description = "Custom database ports for PostgreSQL on EC2 instances"
  type        = list(number)
  default     = [5432, 5433, 5434] # Default PostgreSQL ports
}
