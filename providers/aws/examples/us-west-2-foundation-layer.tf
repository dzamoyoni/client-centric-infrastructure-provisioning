# ============================================================================
# Example: Foundation Layer for us-west-2 Region (CREATE MODE)
# ============================================================================
# This is an example of how to deploy the foundation layer in a NEW region
# using CREATE MODE. Copy this structure to implement new regions.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Backend configuration for us-west-2
    bucket         = "uswest2-terraform-state-production"
    key            = "layers/foundation/production/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# Configure AWS Provider
provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Environment = "production"
      Layer       = "foundation"
      ManagedBy   = "terraform"
      Repository  = "infrastructure"
      Region      = "us-west-2"
    }
  }
}

# ============================================================================
# Foundation Layer Implementation (CREATE MODE)
# ============================================================================

module "foundation" {
  source = "../modules/foundation-layer"

  # Mode Configuration - CREATE MODE for new regions
  import_mode = false # Creates new infrastructure

  # General Configuration
  environment        = "production"
  vpc_name           = "usw2-production-vpc"
  cluster_name       = "us-west-2-cluster-01"
  aws_region         = "us-west-2"
  availability_zones = ["us-west-2a", "us-west-2b"]

  # NEW Infrastructure Configuration
  vpc_cidr        = "172.21.0.0/16" # Different CIDR per region
  private_subnets = ["172.21.1.0/24", "172.21.2.0/24"]
  public_subnets  = ["172.21.101.0/24", "172.21.102.0/24"]

  # Gateway Configuration
  enable_nat_gateway = true
  single_nat_gateway = true

  # DNS Configuration
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Security Groups - Create new ones for new region
  create_security_groups = true

  # VPN Configuration (optional for new regions)
  enable_vpn = false # Or configure as needed:
  # vpn_config = {
  #   customer_gateway_ip = "YOUR_REGION_VPN_IP"
  #   client_cidr        = "YOUR_CLIENT_CIDR"
  #   bgp_asn           = 6500
  # }

  common_tags = {
    Environment = "production"
    Region      = "us-west-2"
    Layer       = "foundation"
    ManagedBy   = "terraform"
    Repository  = "infrastructure"
    CreateMode  = "true"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "foundation_mode" {
  description = "Foundation layer operational mode"
  value       = module.foundation.foundation_mode
}

output "network_summary" {
  description = "Summary of network configuration"
  value       = module.foundation.network_summary
}

output "security_summary" {
  description = "Summary of security groups"
  value       = module.foundation.security_summary
}

output "ssm_parameter_names" {
  description = "SSM parameter names for other layers"
  value       = module.foundation.ssm_parameter_names
}

# ============================================================================
# Deployment Instructions
# ============================================================================
# 
# 1. Copy this file to: regions/us-west-2/layers/01-foundation/production/main.tf
# 2. Create backend config: shared/backend-configs/foundation-production-usw2.hcl
# 3. Initialize: terraform init -backend-config=../../../../../shared/backend-configs/foundation-production-usw2.hcl
# 4. Plan: terraform plan
# 5. Apply: terraform apply
#
# This will create:
# - New VPC with CIDR 172.21.0.0/16
# - New public/private subnets
# - New NAT Gateway and Internet Gateway
# - New security groups
# - SSM parameters identical to us-east-1
#
# Other layers (platform, database, client) can then use the same
# SSM parameter patterns as us-east-1 for consistent deployment.
# ============================================================================
