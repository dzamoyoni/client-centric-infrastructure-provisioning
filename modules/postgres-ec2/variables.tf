# ============================================================================
# PostgreSQL on EC2 Module - Variables
# ============================================================================

# ===================================================================================
# REQUIRED VARIABLES
# ===================================================================================

variable "client_name" {
  description = "Name of the client for resource naming and tagging"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client_name))
    error_message = "Client name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where the database instances will be deployed"
  type        = string
}

variable "master_subnet_id" {
  description = "Subnet ID for the master database instance"
  type        = string
}

variable "replica_subnet_id" {
  description = "Subnet ID for the replica database instance (should be in different AZ)"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI ID for the PostgreSQL instances (should have PostgreSQL pre-installed or use user-data)"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

# ===================================================================================
# INSTANCE CONFIGURATION
# ===================================================================================

variable "master_instance_type" {
  description = "EC2 instance type for the master database"
  type        = string
  default     = "r5.large"
}

variable "replica_instance_type" {
  description = "EC2 instance type for the replica database"
  type        = string
  default     = "r5.large"
}

variable "enable_replica" {
  description = "Enable PostgreSQL replica for high availability"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on EC2 instances"
  type        = bool
  default     = true
}

# ===================================================================================
# POSTGRESQL CONFIGURATION
# ===================================================================================

variable "postgres_version" {
  description = "PostgreSQL version to install"
  type        = string
  default     = "15"
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
}

variable "database_user" {
  description = "Database user for the application"
  type        = string
}

variable "database_password" {
  description = "Password for the database user"
  type        = string
  sensitive   = true
}

variable "replication_user" {
  description = "Username for PostgreSQL replication"
  type        = string
  default     = "replicator"
}

variable "replication_password" {
  description = "Password for PostgreSQL replication user"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

# ===================================================================================
# STORAGE CONFIGURATION
# ===================================================================================

variable "root_volume_type" {
  description = "EBS volume type for root volume"
  type        = string
  default     = "gp3"
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
}

variable "root_volume_iops" {
  description = "IOPS for root volume (only for io1, io2, gp3)"
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "Throughput for root volume (only for gp3)"
  type        = number
  default     = 125
}

variable "data_volume_size" {
  description = "Size of the PostgreSQL data volume in GB"
  type        = number
  default     = 100
}

variable "data_volume_type" {
  description = "EBS volume type for PostgreSQL data"
  type        = string
  default     = "gp3"
}

variable "data_volume_iops" {
  description = "IOPS for data volume"
  type        = number
  default     = 3000
}

variable "data_volume_throughput" {
  description = "Throughput for data volume (only for gp3)"
  type        = number
  default     = 125
}

variable "wal_volume_size" {
  description = "Size of the PostgreSQL WAL volume in GB"
  type        = number
  default     = 20
}

variable "wal_volume_type" {
  description = "EBS volume type for PostgreSQL WAL"
  type        = string
  default     = "gp3"
}

variable "wal_volume_iops" {
  description = "IOPS for WAL volume"
  type        = number
  default     = 3000
}

variable "wal_volume_throughput" {
  description = "Throughput for WAL volume (only for gp3)"
  type        = number
  default     = 125
}

variable "backup_volume_size" {
  description = "Size of the backup volume in GB"
  type        = number
  default     = 50
}

variable "enable_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EBS encryption (optional)"
  type        = string
  default     = ""
}

# ===================================================================================
# NETWORKING AND SECURITY
# ===================================================================================

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL"
  type        = list(string)
  default     = []
}

variable "management_cidr_blocks" {
  description = "CIDR blocks allowed SSH access for management"
  type        = list(string)
  default     = []
}

variable "monitoring_cidr_blocks" {
  description = "CIDR blocks allowed to access monitoring endpoints"
  type        = list(string)
  default     = []
}

variable "enable_ssh_access" {
  description = "Enable SSH access to database instances"
  type        = bool
  default     = true
}

# ===================================================================================
# DNS CONFIGURATION
# ===================================================================================

variable "create_dns_records" {
  description = "Create Route 53 DNS records for database endpoints"
  type        = bool
  default     = false
}

variable "private_zone_id" {
  description = "Route 53 private hosted zone ID for DNS records"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for DNS records"
  type        = string
  default     = ""
}

# ===================================================================================
# MONITORING AND BACKUP
# ===================================================================================

variable "enable_monitoring" {
  description = "Enable detailed monitoring and PostgreSQL exporter"
  type        = bool
  default     = true
}

variable "additional_iam_policies" {
  description = "Additional IAM policy ARNs to attach to instance role"
  type        = list(string)
  default     = []
}

# ===================================================================================
# TAGGING
# ===================================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
