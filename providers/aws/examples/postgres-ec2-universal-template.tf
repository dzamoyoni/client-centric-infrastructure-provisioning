# ============================================================================
# Universal PostgreSQL on EC2 Template
# ============================================================================
# This template can be used in ANY AWS region for deploying highly available
# PostgreSQL databases using the postgres-ec2 module. Simply adjust the
# variables and network configuration for your specific region and clients.
# ============================================================================

# Example regions where this template works:
# - us-east-1 (Virginia) ✅
# - us-west-2 (Oregon) ✅  
# - eu-west-1 (Ireland) ✅
# - ap-southeast-1 (Singapore) ✅
# - af-south-1 (Cape Town) ✅
# - Any other AWS region ✅

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Backend configuration will be provided via -backend-config
    # Adjust for your region: s3://your-terraform-state-bucket-{region}
  }
}

# Configure AWS Provider for any region
provider "aws" {
  region = var.aws_region # Set via terraform.tfvars or environment

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "postgres-ec2"
      Region      = var.aws_region
    }
  }
}

# ============================================================================
# VARIABLES - Customize for your region and clients
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  # Examples: "us-east-1", "us-west-2", "eu-west-1", "af-south-1", "ap-southeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID for the target region"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (minimum 2 for HA across AZs)"
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets required for high availability."
  }
}

variable "key_name" {
  description = "EC2 Key Pair name for the region"
  type        = string
}

variable "clients" {
  description = "Client configurations for PostgreSQL databases"
  type = map(object({
    database_name         = string
    database_user         = string
    database_password     = string
    replication_password  = string
    instance_type_master  = optional(string, "r5.large")
    instance_type_replica = optional(string, "r5.large")
    data_volume_size      = optional(number, 100)
    data_volume_type      = optional(string, "gp3")
    data_volume_iops      = optional(number, 3000)
    backup_retention_days = optional(number, 7)
    allowed_cidrs         = list(string)
    tags                  = optional(map(string), {})
  }))
}

# ============================================================================
# DATA SOURCES - Works in any region
# ============================================================================

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Ubuntu 22.04 LTS AMI for the region
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get VPC information
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Get subnet information for AZ placement
data "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

# ============================================================================
# LOCALS - Dynamic configuration based on region
# ============================================================================

locals {
  # Region-specific configuration
  region_name = data.aws_region.current.name

  # Ensure we have subnets in different AZs for HA
  subnet_az_map = {
    for idx, subnet in data.aws_subnet.private_subnets :
    subnet.availability_zone => subnet.id
  }

  # Get first two different AZs for master/replica placement
  availability_zones = keys(local.subnet_az_map)
  master_az          = local.availability_zones[0]
  replica_az         = length(local.availability_zones) > 1 ? local.availability_zones[1] : local.availability_zones[0]

  # Common tags for all resources
  common_tags = {
    Region      = local.region_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "postgres-ec2"
    Deployment  = "universal-template"
  }
}

# ============================================================================
# POSTGRESQL DATABASES - One per client
# ============================================================================

module "client_databases" {
  source = "../modules/postgres-ec2" # Adjust path based on your structure

  for_each = var.clients

  # Client identification
  client_name = each.key
  environment = var.environment

  # Network configuration - automatically uses different AZs
  vpc_id            = var.vpc_id
  master_subnet_id  = local.subnet_az_map[local.master_az]
  replica_subnet_id = local.subnet_az_map[local.replica_az]

  # Instance configuration - region-appropriate AMI
  ami_id                = data.aws_ami.ubuntu.id
  key_name              = var.key_name
  master_instance_type  = each.value.instance_type_master
  replica_instance_type = each.value.instance_type_replica

  # PostgreSQL configuration
  postgres_version     = "15" # Latest stable version
  database_name        = each.value.database_name
  database_user        = each.value.database_user
  database_password    = each.value.database_password
  replication_password = each.value.replication_password

  # Storage configuration
  data_volume_size = each.value.data_volume_size
  data_volume_type = each.value.data_volume_type
  data_volume_iops = each.value.data_volume_iops

  # Security configuration
  enable_encryption      = true
  allowed_cidr_blocks    = each.value.allowed_cidrs
  management_cidr_blocks = [data.aws_vpc.selected.cidr_block]

  # Monitoring and backup
  enable_monitoring     = true
  backup_retention_days = each.value.backup_retention_days

  # Tags - merge common tags with client-specific tags
  tags = merge(
    local.common_tags,
    each.value.tags,
    {
      Client = each.key
      Name   = "${each.key}-${var.environment}-database"
    }
  )
}

# ============================================================================
# OUTPUTS - Database connection information
# ============================================================================

output "database_endpoints" {
  description = "Database connection endpoints for all clients"
  value = {
    for client_name, db in module.client_databases : client_name => {
      master_endpoint     = db.master_endpoint
      replica_endpoint    = db.replica_endpoint
      database_port       = db.database_port
      database_name       = db.database_name
      master_instance_id  = db.master_instance_id
      replica_instance_id = db.replica_instance_id
      security_group_id   = db.security_group_id
    }
  }
  sensitive = true
}

output "deployment_summary" {
  description = "Summary of the PostgreSQL deployment"
  value = {
    region            = local.region_name
    environment       = var.environment
    total_clients     = length(var.clients)
    master_az         = local.master_az
    replica_az        = local.replica_az
    high_availability = local.master_az != local.replica_az
  }
}

# ============================================================================
# EXAMPLE TERRAFORM.TFVARS FOR DIFFERENT REGIONS
# ============================================================================

# For US-East-1 (Virginia):
# aws_region = "us-east-1"
# vpc_id = "vpc-0123456789abcdef0"
# private_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0987654321fedcba0"]
# key_name = "my-us-east-1-keypair"

# For AF-South-1 (Cape Town):
# aws_region = "af-south-1"
# vpc_id = "vpc-0abcdef123456789"
# private_subnet_ids = ["subnet-0abcdef123456789", "subnet-0123456789abcdef"]
# key_name = "my-af-south-1-keypair"

# For EU-West-1 (Ireland):
# aws_region = "eu-west-1"
# vpc_id = "vpc-0987654321fedcba0"
# private_subnet_ids = ["subnet-0987654321fedcba0", "subnet-0abcdef123456789"]
# key_name = "my-eu-west-1-keypair"

# Client configuration example:
# clients = {
#   "client-a" = {
#     database_name        = "client_a_app"
#     database_user        = "client_a_user"
#     database_password    = "secure_password_123"
#     replication_password = "repl_password_456"
#     instance_type_master = "r5.large"
#     data_volume_size     = 100
#     allowed_cidrs        = ["10.0.0.0/16", "172.16.0.0/12"]
#     backup_retention_days = 14
#     tags = {
#       Owner = "client-a-team"
#       CostCenter = "client-a-production"
#     }
#   }
#   "client-b" = {
#     database_name        = "client_b_core"
#     database_user        = "client_b_user"
#     database_password    = "another_secure_password"
#     replication_password = "another_repl_password"
#     instance_type_master = "r5.xlarge"
#     data_volume_size     = 500
#     allowed_cidrs        = ["192.168.0.0/16"]
#     backup_retention_days = 30
#     tags = {
#       Owner = "client-b-database-team"
#       BusinessUnit = "enterprise"
#     }
#   }
# }
