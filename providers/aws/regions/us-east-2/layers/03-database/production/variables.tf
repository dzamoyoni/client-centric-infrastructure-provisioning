# ============================================================================
# Layer 3: Database Layer Variables - US-East-2 Production
# ============================================================================
# Variables for high-availability PostgreSQL database layer with enterprise features
# Supports master-replica setup, encryption, monitoring, and client isolation
# ============================================================================

# ===================================================================================
# CORE CONFIGURATION - Project Identification
# ===================================================================================

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

# ===================================================================================
# REMOTE STATE CONFIGURATION
# ===================================================================================

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state storage"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region where Terraform state bucket is located"
  type        = string
}

# ===================================================================================
# INFRASTRUCTURE CONFIGURATION - Database Instances
# ===================================================================================

variable "postgres_ami_id" {
  description = "AMI ID for PostgreSQL instances (pre-configured PostgreSQL AMI)"
  type        = string
}

variable "key_name" {
  description = "AWS Key Pair name for EC2 instance access"
  type        = string
}

variable "master_instance_type" {
  description = "EC2 instance type for PostgreSQL master (memory-optimized for production)"
  type        = string

  validation {
    condition = contains([
      "r5.large", "r5.xlarge", "r5.2xlarge", "r5.4xlarge",
      "r6i.large", "r6i.xlarge", "r6i.2xlarge", "r6i.4xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.master_instance_type)
    error_message = "Instance type must be a supported memory-optimized instance for database workloads."
  }
}

variable "replica_instance_type" {
  description = "EC2 instance type for PostgreSQL replica (can be smaller than master)"
  type        = string

  validation {
    condition = contains([
      "r5.large", "r5.xlarge", "r5.2xlarge", "r5.4xlarge",
      "r6i.large", "r6i.xlarge", "r6i.2xlarge", "r6i.4xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.replica_instance_type)
    error_message = "Instance type must be a supported memory-optimized instance for database workloads."
  }
}

# ===================================================================================
# SECURITY CONFIGURATION - Network Access Control
# ===================================================================================

variable "management_cidr_blocks" {
  description = "CIDR blocks allowed for management access (SSH, monitoring)"
  type        = list(string)
}

# ===================================================================================
# STORAGE CONFIGURATION
# ===================================================================================

variable "data_volume_size" {
  description = "Size of the data volume in GB"
  type        = number

  validation {
    condition     = var.data_volume_size >= 20 && var.data_volume_size <= 16384
    error_message = "Data volume size must be between 20 and 16384 GB."
  }
}

variable "wal_volume_size" {
  description = "Size of the WAL volume in GB"
  type        = number

  validation {
    condition     = var.wal_volume_size >= 10 && var.wal_volume_size <= 1000
    error_message = "WAL volume size must be between 10 and 1000 GB."
  }
}

variable "backup_volume_size" {
  description = "Size of the backup volume in GB"
  type        = number

  validation {
    condition     = var.backup_volume_size >= 20 && var.backup_volume_size <= 16384
    error_message = "Backup volume size must be between 20 and 16384 GB."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain database backups"
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

# ===================================================================================
# DYNAMIC CLIENT CONFIGURATION
# ===================================================================================

variable "clients" {
  description = "Map of client configurations for dynamic provisioning"
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string
    
    network = object({
      cidr_offset = number
    })
    
    eks = object({
      enabled         = bool
      instance_types  = list(string)
      min_size        = number
      max_size        = number
      desired_size    = number
      disk_size       = number
      capacity_type   = string
    })
    
    compute = object({
      analytics_enabled = bool
      instance_type     = string
      root_volume_size  = number
      data_volume_size  = number
    })
    
    storage = object({
      enable_dedicated_buckets = bool
      backup_retention_days    = number
    })
    
    security = object({
      custom_ports   = list(number)
      database_ports = list(number)
    })
    
    metadata = object({
      full_name       = string
      industry        = string
      contact_email   = string
      compliance      = list(string)
      cost_center     = string
      business_unit   = string
    })
  }))
}

# ===================================================================================
# DATABASE SECRETS - Dynamic per client
# ===================================================================================

variable "database_passwords" {
  description = "Map of database passwords per client (sensitive)"
  type        = map(string)
  sensitive   = true
  
  validation {
    condition     = alltrue([for pwd in values(var.database_passwords) : length(pwd) >= 12])
    error_message = "All passwords must be at least 12 characters long."
  }
}

variable "replication_passwords" {
  description = "Map of replication passwords per client (sensitive)"
  type        = map(string)
  sensitive   = true
  
  validation {
    condition     = alltrue([for pwd in values(var.replication_passwords) : length(pwd) >= 12])
    error_message = "All replication passwords must be at least 12 characters long."
  }
}
