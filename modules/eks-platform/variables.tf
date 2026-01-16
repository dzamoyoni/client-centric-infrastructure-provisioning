# EKS Cluster Wrapper Module - Variables
# Standardized inputs for consistent EKS deployments across all environments

# CORE CONFIGURATION
variable "project_name" {
  description = "Project name for resource naming (DEPRECATED - not used in client-centric architecture)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.project_name == "" || can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens only."
  }
}

variable "cluster_name" {
  description = "EKS cluster name (overrides default project_name based naming)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be: production, staging, or development."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

# CLUSTER CONFIGURATION
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
  validation {
    condition     = can(regex("^1\\.(30|31)$", var.cluster_version))
    error_message = "Cluster version must be 1.30 or 1.31."
  }
}

# NETWORK CONFIGURATION (from foundation layer)
variable "vpc_id" {
  description = "VPC ID from foundation layer"
  type        = string
}

variable "platform_subnet_ids" {
  description = "Platform subnet IDs from foundation layer"
  type        = list(string)
}

# SECURITY CONFIGURATION
variable "enable_public_access" {
  description = "Enable public endpoint access"
  type        = bool
  default     = true
}

variable "management_cidr_blocks" {
  description = "CIDR blocks for management access"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# NODE GROUPS CONFIGURATION
variable "node_groups" {
  description = "Map of EKS managed node group definitions"
  type = map(object({
    name_suffix    = string       # Short name for the node group
    instance_types = list(string) # EC2 instance types
    min_size       = number       # Minimum number of nodes
    max_size       = number       # Maximum number of nodes
    desired_size   = number       # Desired number of nodes
    disk_size      = number       # EBS disk size in GB

    # Optional client-specific configuration
    client  = optional(string, "platform") # Client identifier
    purpose = optional(string)             # Node group purpose

    # Optional custom labels and tags
    labels = optional(map(string), {})
    tags   = optional(map(string), {})
  }))

  validation {
    condition = alltrue([
      for name, ng in var.node_groups :
      ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size
    ])
    error_message = "For each node group: min_size <= desired_size <= max_size."
  }

  validation {
    condition = alltrue([
      for name, ng in var.node_groups :
      ng.disk_size >= 20 && ng.disk_size <= 1000
    ])
    error_message = "Disk size must be between 20 and 1000 GB."
  }
}

# ACCESS CONFIGURATION
variable "access_entries" {
  description = "Map of access entries for the cluster"
  type = map(object({
    kubernetes_groups = optional(list(string), [])
    principal_arn     = string
    policy_associations = optional(map(object({
      policy_arn = string
      access_scope = object({
        type       = string
        namespaces = optional(list(string))
      })
    })), {})
  }))
  default = {}
}

# ADDITIONAL TAGS
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# LOG ROTATION CONFIGURATION
variable "container_log_max_size" {
  description = "Maximum size of container log file before rotation (e.g., 100Mi, 50Mi)"
  type        = string
  default     = "100Mi"
}

variable "container_log_max_files" {
  description = "Maximum number of rotated log files to retain"
  type        = number
  default     = 3
  
  validation {
    condition     = var.container_log_max_files >= 1 && var.container_log_max_files <= 10
    error_message = "container_log_max_files must be between 1 and 10."
  }
}
