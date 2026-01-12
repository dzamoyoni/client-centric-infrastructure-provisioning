# ============================================================================
# Unified SSM Parameters for Cross-Layer Communication
# ============================================================================
# Creates identical SSM parameter structure regardless of import/create mode
# This ensures consistent interface for all other layers across all regions
# ============================================================================

# ============================================================================
# Core Infrastructure SSM Parameters
# ============================================================================

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/terraform/${var.environment}/foundation/vpc_id"
  type  = "String"
  value = local.vpc_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "/terraform/${var.environment}/foundation/vpc_cidr"
  type  = "String"
  value = local.vpc_cidr_block

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "private_subnets" {
  name  = "/terraform/${var.environment}/foundation/private_subnets"
  type  = "StringList"
  value = join(",", local.private_subnet_ids)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "public_subnets" {
  name  = "/terraform/${var.environment}/foundation/public_subnets"
  type  = "StringList"
  value = join(",", local.public_subnet_ids)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "private_subnet_cidrs" {
  name  = "/terraform/${var.environment}/foundation/private_subnet_cidrs"
  type  = "StringList"
  value = join(",", local.private_subnet_cidrs)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "public_subnet_cidrs" {
  name  = "/terraform/${var.environment}/foundation/public_subnet_cidrs"
  type  = "StringList"
  value = join(",", local.public_subnet_cidrs)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Gateway SSM Parameters
# ============================================================================

resource "aws_ssm_parameter" "internet_gateway_id" {
  count = local.internet_gateway_id != "" ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/internet_gateway_id"
  type  = "String"
  value = local.internet_gateway_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "nat_gateway_ids" {
  count = length(local.nat_gateway_ids) > 0 ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/nat_gateway_ids"
  type  = "StringList"
  value = join(",", local.nat_gateway_ids)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Security Group SSM Parameters
# ============================================================================

resource "aws_ssm_parameter" "eks_cluster_sg_id" {
  count = local.eks_cluster_sg_id != "" ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/eks_cluster_security_group_id"
  type  = "String"
  value = local.eks_cluster_sg_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "security"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "database_sg_id" {
  count = local.database_sg_id != "" ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/database_security_group_id"
  type  = "String"
  value = local.database_sg_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "security"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "alb_sg_id" {
  count = local.alb_sg_id != "" ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/alb_security_group_id"
  type  = "String"
  value = local.alb_sg_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "security"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# VPN SSM Parameters
# ============================================================================

resource "aws_ssm_parameter" "vpn_enabled" {
  name  = "/terraform/${var.environment}/foundation/vpn_enabled"
  type  = "String"
  value = tostring(local.vpn_enabled)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "vpn_gateway_id" {
  count = local.vpn_gateway_id != "" ? 1 : 0
  name  = "/terraform/${var.environment}/foundation/vpn_gateway_id"
  type  = "String"
  value = local.vpn_gateway_id

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "infrastructure"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Metadata and Versioning SSM Parameters
# ============================================================================

resource "aws_ssm_parameter" "deployed" {
  name  = "/terraform/${var.environment}/foundation/deployed"
  type  = "String"
  value = "true"

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "metadata"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "version" {
  name  = "/terraform/${var.environment}/foundation/version"
  type  = "String"
  value = "1.0.0"

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "metadata"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "mode" {
  name  = "/terraform/${var.environment}/foundation/mode"
  type  = "String"
  value = local.mode_name

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "metadata"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "region" {
  name  = "/terraform/${var.environment}/foundation/region"
  type  = "String"
  value = var.aws_region

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "metadata"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "availability_zones" {
  name  = "/terraform/${var.environment}/foundation/availability_zones"
  type  = "StringList"
  value = join(",", var.availability_zones)

  tags = merge(local.common_tags, {
    Layer      = "foundation"
    Type       = "metadata"
    ImportMode = tostring(local.is_import_mode)
  })

  lifecycle {
    prevent_destroy = true
  }
}
