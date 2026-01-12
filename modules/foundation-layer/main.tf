# ============================================================================
# Unified Foundation Layer Module
# ============================================================================
# This module provides foundational networking and security infrastructure
# for multi-tenant architecture with two operational modes:
#
# IMPORT MODE: References existing infrastructure
# CREATE MODE: Creates new infrastructure (future regions)
#
# Both modes provide identical SSM parameter outputs for consistency.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# Mode Detection and Configuration
# ============================================================================

locals {
  # Determine operational mode
  is_import_mode = var.import_mode != null ? var.import_mode : (var.existing_vpc_id != "" && var.existing_vpc_id != null)
  is_create_mode = !local.is_import_mode

  # Mode validation
  mode_name = local.is_import_mode ? "IMPORT" : "CREATE"

  # Common configuration
  common_tags = merge(var.common_tags, {
    FoundationMode = local.mode_name
    Region         = var.aws_region
    Environment    = var.environment
  })
}

# Validation checks
resource "null_resource" "mode_validation" {
  count = local.is_import_mode && var.existing_vpc_id == "" ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: Import mode requires existing_vpc_id' && exit 1"
  }
}

# ============================================================================
# IMPORT MODE: Reference Existing Infrastructure
# ============================================================================

# Data sources for existing infrastructure (only in import mode)
data "aws_vpc" "existing" {
  count = local.is_import_mode ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_subnet" "existing_private" {
  count = local.is_import_mode ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

data "aws_subnet" "existing_public" {
  count = local.is_import_mode ? length(var.existing_public_subnet_ids) : 0
  id    = var.existing_public_subnet_ids[count.index]
}

data "aws_internet_gateway" "existing" {
  count = local.is_import_mode && var.existing_igw_id != "" ? 1 : 0

  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

data "aws_nat_gateways" "existing" {
  count  = local.is_import_mode ? 1 : 0
  vpc_id = var.existing_vpc_id
}

data "aws_vpn_gateway" "existing" {
  count = local.is_import_mode && var.existing_vpn_gateway_id != "" ? 1 : 0
  id    = var.existing_vpn_gateway_id
}

# ============================================================================
# CREATE MODE: New Infrastructure
# ============================================================================

# VPC Module (only in create mode)
module "vpc" {
  count   = local.is_create_mode ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # NAT Gateway configuration
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # DNS configuration
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  # VPC Flow Logs
  enable_flow_log                      = var.enable_flow_log
  create_flow_log_cloudwatch_log_group = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_log
  flow_log_destination_type            = var.flow_log_destination_type

  # Tagging
  tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })

  public_subnet_tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
    "SubnetType"                                = "public"
  })

  private_subnet_tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
    "SubnetType"                                = "private"
  })
}

# ============================================================================
# Unified Data Layer - Works for Both Modes
# ============================================================================

locals {
  # VPC information (unified from both modes)
  vpc_id         = local.is_import_mode ? data.aws_vpc.existing[0].id : module.vpc[0].vpc_id
  vpc_cidr_block = local.is_import_mode ? data.aws_vpc.existing[0].cidr_block : module.vpc[0].vpc_cidr_block

  # Subnet information (unified)
  private_subnet_ids = local.is_import_mode ? var.existing_private_subnet_ids : module.vpc[0].private_subnets
  public_subnet_ids  = local.is_import_mode ? var.existing_public_subnet_ids : module.vpc[0].public_subnets

  private_subnet_cidrs = local.is_import_mode ? [
    for subnet in data.aws_subnet.existing_private : subnet.cidr_block
  ] : module.vpc[0].private_subnets_cidr_blocks

  public_subnet_cidrs = local.is_import_mode ? [
    for subnet in data.aws_subnet.existing_public : subnet.cidr_block
  ] : module.vpc[0].public_subnets_cidr_blocks

  # Gateway information (unified)
  internet_gateway_id = local.is_import_mode ? (
    var.existing_igw_id != "" ? var.existing_igw_id : (
      length(data.aws_internet_gateway.existing) > 0 ? data.aws_internet_gateway.existing[0].id : ""
    )
  ) : module.vpc[0].igw_id

  nat_gateway_ids = local.is_import_mode ? (
    length(var.existing_nat_gateway_ids) > 0 ? var.existing_nat_gateway_ids : (
      length(data.aws_nat_gateways.existing) > 0 ? data.aws_nat_gateways.existing[0].ids : []
    )
  ) : module.vpc[0].natgw_ids

  # VPN information (unified)
  vpn_gateway_id = local.is_import_mode ? var.existing_vpn_gateway_id : ""
  vpn_enabled    = local.is_import_mode ? (var.existing_vpn_gateway_id != "") : var.enable_vpn
}

# ============================================================================
# Debug and Validation Outputs (for development)
# ============================================================================

resource "null_resource" "mode_info" {
  provisioner "local-exec" {
    command = "echo 'Foundation Layer Mode: ${local.mode_name} | VPC: ${local.vpc_id} | Region: ${var.aws_region}'"
  }

  triggers = {
    mode   = local.mode_name
    vpc_id = local.vpc_id
    region = var.aws_region
  }
}
