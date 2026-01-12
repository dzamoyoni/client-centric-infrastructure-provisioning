# ============================================================================
# Security Groups - Unified for Both Modes
# ============================================================================

# Data sources for existing security groups (import mode)
data "aws_security_group" "existing_eks_cluster" {
  count = local.is_import_mode && !var.create_security_groups && var.existing_eks_cluster_sg_id != "" ? 1 : 0
  id    = var.existing_eks_cluster_sg_id
}

data "aws_security_group" "existing_database" {
  count = local.is_import_mode && !var.create_security_groups && var.existing_database_sg_id != "" ? 1 : 0
  id    = var.existing_database_sg_id
}

data "aws_security_group" "existing_alb" {
  count = local.is_import_mode && !var.create_security_groups && var.existing_alb_sg_id != "" ? 1 : 0
  id    = var.existing_alb_sg_id
}

# ============================================================================
# New Security Groups (when needed)
# ============================================================================

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  count       = var.create_security_groups ? 1 : 0
  name        = "${var.vpc_name}-foundation-eks-cluster-sg"
  description = "Foundation layer security group for EKS cluster control plane"
  vpc_id      = local.vpc_id

  # Allow HTTPS traffic from VPC CIDR
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow HTTPS from VPC"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-foundation-eks-cluster-sg"
    Type = "eks-cluster"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Database Security Group
resource "aws_security_group" "database" {
  count       = var.create_security_groups ? 1 : 0
  name        = "${var.vpc_name}-foundation-database-sg"
  description = "Foundation layer security group for database instances"
  vpc_id      = local.vpc_id

  # PostgreSQL access from VPC CIDR
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow PostgreSQL from VPC"
  }

  # MySQL access from VPC CIDR
  # ingress {
  #   from_port   = 3306
  #   to_port     = 3306
  #   protocol    = "tcp"
  #   cidr_blocks = [local.vpc_cidr_block]
  #   description = "Allow MySQL from VPC"
  # }

  # Allow outbound to VPC (for health checks, etc.)
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
    description = "Allow outbound to VPC"
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-foundation-database-sg"
    Type = "database"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  count       = var.create_security_groups ? 1 : 0
  name        = "${var.vpc_name}-foundation-alb-sg"
  description = "Foundation layer security group for Application Load Balancer"
  vpc_id      = local.vpc_id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from internet"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-foundation-alb-sg"
    Type = "load-balancer"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# Unified Security Group References
# ============================================================================

locals {
  # Security group IDs (unified from both modes and existing/new)
  eks_cluster_sg_id = (
    var.create_security_groups ?
    aws_security_group.eks_cluster[0].id :
    (local.is_import_mode ? var.existing_eks_cluster_sg_id : "")
  )

  database_sg_id = (
    var.create_security_groups ?
    aws_security_group.database[0].id :
    (local.is_import_mode ? var.existing_database_sg_id : "")
  )

  alb_sg_id = (
    var.create_security_groups ?
    aws_security_group.alb[0].id :
    (local.is_import_mode ? var.existing_alb_sg_id : "")
  )
}
