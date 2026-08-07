# ============================================================================
# AWS Application Load Balancer Module - Per Client
# ============================================================================
# Purpose: Provides Layer 7 load balancing for client EKS clusters with
#          support for internet-facing, internal, or dual ALB configurations.
#          Routes traffic to Istio Ingress Gateway via NodePort.
#
# Architecture:
#   External Traffic → ALB (30443/30080) → EKS NodePort → Istio Gateway (80)
#                                                         → VirtualServices
#                                                         → Backend Services
#
# Features:
#   - Dual ALB support (internet-facing + internal)
#   - Custom port configuration (default: 30443 HTTPS, 30080 HTTP)
#   - SSL/TLS termination with AWS Certificate Manager
#   - WAF integration for internet-facing ALBs
#   - Health checks to Istio Ingress Gateway
#   - Client-specific tagging and naming
#   - Security group automation
# ============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  # Determine which ALB types to create
  create_internet_facing = contains(["internet-facing", "both"], var.alb_type)
  create_internal        = contains(["internal", "both"], var.alb_type)
  
  # Common naming prefix
  name_prefix = "${var.client_id}-${var.environment}"

  _name_length_check = (
  length("${var.client_id}-${var.environment}-internal-alb") <= 32
  ? true
  : tobool("ERROR: ALB name '${var.client_id}-${var.environment}-internal-alb' exceeds 32 characters...")
  )

  _waf_config_check = (
  !var.enable_waf || var.waf_acl_arn != null
  ? true
  : tobool("ERROR: enable_waf is true but waf_acl_arn is null. Provide a WAF ACL ARN.")
  )
  
  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      Client      = var.client_id
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "alb-per-client"
    }
  )
}

# ============================================================================
# Internet-Facing Application Load Balancer
# ============================================================================

resource "aws_lb" "internet_facing" {
  count = local.create_internet_facing ? 1 : 0
  
  # name               = length("${local.name_prefix}-public-alb") <=32
  name = "${local.name_prefix}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_public[0].id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  enable_waf_fail_open             = false
  
  drop_invalid_header_fields = true
  
#   dynamic "access_logs" {
#   for_each = var.enable_access_logs ? [1] : []

#   content {
#     enabled = true
#     bucket  = var.access_logs_bucket
#     prefix  = "${var.client_id}/public-alb"
#   }
# }
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-public-alb"
      ALB-Type    = "internet-facing"
      Exposure    = "Public"
      Description = "Internet-facing ALB for ${var.client_id} - Routes to Istio Ingress Gateway"
    }
  )
}

# ============================================================================
# Internal Application Load Balancer
# ============================================================================

resource "aws_lb" "internal" {
  count = local.create_internal ? 1 : 0
  
  # name               = length("${local.name_prefix}-internal-alb") <=32
  name = "${local.name_prefix}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_internal[0].id]
  subnets            = var.private_subnet_ids
  
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  
  drop_invalid_header_fields = true
  
  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "${var.client_id}/internal-alb"
    enabled = var.enable_access_logs
  }
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-internal-alb"
      ALB-Type    = "internal"
      Exposure    = "Private"
      Description = "Internal ALB for ${var.client_id} - VPN/Corporate access only"
    }
  )
}

# ============================================================================
# Target Groups - HTTPS (Port 30443)
# ============================================================================

resource "aws_lb_target_group" "https_public" {
  count = local.create_internet_facing ? 1 : 0
  
  name     = "${local.name_prefix}-pub-https-tg"
  port     = var.https_nodeport
  protocol = "HTTP"  # NodePort to Istio is HTTP (Istio handles internal mTLS)
  vpc_id   = var.vpc_id
  
  target_type          = "instance"
  deregistration_delay = 30
  
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.http_nodeport
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
  
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = var.enable_sticky_sessions
  }
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-pub-https-tg"
      Port        = var.https_nodeport
      Protocol    = "HTTP"
      Description = "Public HTTPS target group for ${var.client_id}"
    }
  )
}

resource "aws_lb_target_group" "https_internal" {
  count = local.create_internal ? 1 : 0
  
  name     = "${local.name_prefix}-int-https-tg"
  port     = var.https_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  target_type          = "instance"
  deregistration_delay = 30
  
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.http_nodeport
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
  
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = var.enable_sticky_sessions
  }
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-int-https-tg"
      Port        = var.https_nodeport
      Protocol    = "HTTP"
      Description = "Internal HTTPS target group for ${var.client_id}"
    }
  )
}

# ============================================================================
# Target Groups - HTTP (Port 30080)
# ============================================================================

resource "aws_lb_target_group" "http_public" {
  count = local.create_internet_facing ? 1 : 0
  
  name     = "${local.name_prefix}-pub-http-tg"
  port     = var.http_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  target_type          = "instance"
  deregistration_delay = 30
  
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.http_nodeport
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-pub-http-tg"
      Port        = var.http_nodeport
      Protocol    = "HTTP"
      Description = "Public HTTP target group for ${var.client_id}"
    }
  )
}

resource "aws_lb_target_group" "http_internal" {
  count = local.create_internal ? 1 : 0
  
  name     = "${local.name_prefix}-int-http-tg"
  port     = var.http_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  target_type          = "instance"
  deregistration_delay = 30
  
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = var.http_nodeport
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-int-http-tg"
      Port        = var.http_nodeport
      Protocol    = "HTTP"
      Description = "Internal HTTP target group for ${var.client_id}"
    }
  )
}

# ============================================================================
# Listeners - Public ALB HTTPS (Port 30443)
# ============================================================================

resource "aws_lb_listener" "public_https" {
  count = local.create_internet_facing ? 1 : 0
  
  load_balancer_arn = aws_lb.internet_facing[0].arn
  port              = var.https_external_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_public[0].arn
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-pub-https-listener"
      Port = var.https_external_port
    }
  )
}

# ============================================================================
# Listeners - Public ALB HTTP (Port 30080) - Redirect to HTTPS
# ============================================================================

resource "aws_lb_listener" "public_http" {
  count = local.create_internet_facing ? 1 : 0
  
  load_balancer_arn = aws_lb.internet_facing[0].arn
  port              = var.http_external_port
  protocol          = "HTTP"
  
  default_action {
    type = var.redirect_http_to_https ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.redirect_http_to_https ? [1] : []
      content {
        port        = tostring(var.https_external_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    target_group_arn = var.redirect_http_to_https ? null : aws_lb_target_group.http_public[0].arn
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-pub-http-listener"
      Port = var.http_external_port
    }
  )
}

# ============================================================================
# Listeners - Internal ALB HTTPS (Port 30443)
# ============================================================================

resource "aws_lb_listener" "internal_https" {
  count = local.create_internal ? 1 : 0
  
  load_balancer_arn = aws_lb.internal[0].arn
  port              = var.https_external_port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.ssl_certificate_arn_internal != null ? var.ssl_certificate_arn_internal : var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_internal[0].arn
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-int-https-listener"
      Port = var.https_external_port
    }
  )
}

# ============================================================================
# Listeners - Internal ALB HTTP (Port 30080)
# ============================================================================

resource "aws_lb_listener" "internal_http" {
  count = local.create_internal ? 1 : 0
  
  load_balancer_arn = aws_lb.internal[0].arn
  port              = var.http_external_port
  protocol          = "HTTP"
  
  default_action {
    type = var.redirect_http_to_https ? "redirect" : "forward"
    
    dynamic "redirect" {
      for_each = var.redirect_http_to_https ? [1] : []
      content {
        port        = tostring(var.https_external_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    target_group_arn = var.redirect_http_to_https ? null : aws_lb_target_group.http_internal[0].arn
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-int-http-listener"
      Port = var.http_external_port
    }
  )
}

# ============================================================================
# Security Group - Public ALB
# ============================================================================

resource "aws_security_group" "alb_public" {
  count = local.create_internet_facing ? 1 : 0
  
  name_prefix = "${local.name_prefix}-pub-alb-sg-"
  description = "Security group for public ALB - ${var.client_id}"
  vpc_id      = var.vpc_id
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-pub-alb-sg"
      Description = "Public ALB security group for ${var.client_id}"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Public ALB - Ingress HTTPS
resource "aws_security_group_rule" "alb_public_ingress_https" {
  count = local.create_internet_facing ? 1 : 0
  
  type              = "ingress"
  from_port         = var.https_external_port
  to_port           = var.https_external_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks_public
  security_group_id = aws_security_group.alb_public[0].id
  description       = "Allow HTTPS from Internet"
}

# Public ALB - Ingress HTTP
resource "aws_security_group_rule" "alb_public_ingress_http" {
  count = local.create_internet_facing ? 1 : 0
  
  type              = "ingress"
  from_port         = var.http_external_port
  to_port           = var.http_external_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks_public
  security_group_id = aws_security_group.alb_public[0].id
  description       = "Allow HTTP from Internet (redirects to HTTPS)"
}

# Public ALB - Egress to EKS NodePort HTTPS
resource "aws_security_group_rule" "alb_public_egress_https" {
  count = local.create_internet_facing ? 1 : 0
  
  type                     = "egress"
  from_port                = var.https_nodeport
  to_port                  = var.https_nodeport
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.alb_public[0].id
  description              = "Allow traffic to EKS NodePort HTTPS"
}

# Public ALB - Egress to EKS NodePort HTTP
resource "aws_security_group_rule" "alb_public_egress_http" {
  count = local.create_internet_facing ? 1 : 0
  
  type                     = "egress"
  from_port                = var.http_nodeport
  to_port                  = var.http_nodeport
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.alb_public[0].id
  description              = "Allow traffic to EKS NodePort HTTP"
}

# ============================================================================
# Security Group - Internal ALB
# ============================================================================

resource "aws_security_group" "alb_internal" {
  count = local.create_internal ? 1 : 0
  
  name_prefix = "${local.name_prefix}-int-alb-sg-"
  description = "Security group for internal ALB - ${var.client_id}"
  vpc_id      = var.vpc_id
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-int-alb-sg"
      Description = "Internal ALB security group for ${var.client_id}"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Internal ALB - Ingress HTTPS
resource "aws_security_group_rule" "alb_internal_ingress_https" {
  count = local.create_internal ? 1 : 0
  
  type              = "ingress"
  from_port         = var.https_external_port
  to_port           = var.https_external_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks_internal
  security_group_id = aws_security_group.alb_internal[0].id
  description       = "Allow HTTPS from VPN/Corporate network"
}

# Internal ALB - Ingress HTTP
resource "aws_security_group_rule" "alb_internal_ingress_http" {
  count = local.create_internal ? 1 : 0
  
  type              = "ingress"
  from_port         = var.http_external_port
  to_port           = var.http_external_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks_internal
  security_group_id = aws_security_group.alb_internal[0].id
  description       = "Allow HTTP from VPN/Corporate network"
}

# Internal ALB - Egress to EKS NodePort HTTPS
resource "aws_security_group_rule" "alb_internal_egress_https" {
  count = local.create_internal ? 1 : 0
  
  type                     = "egress"
  from_port                = var.https_nodeport
  to_port                  = var.https_nodeport
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.alb_internal[0].id
  description              = "Allow traffic to EKS NodePort HTTPS"
}

# Internal ALB - Egress to EKS NodePort HTTP
resource "aws_security_group_rule" "alb_internal_egress_http" {
  count = local.create_internal ? 1 : 0
  
  type                     = "egress"
  from_port                = var.http_nodeport
  to_port                  = var.http_nodeport
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_security_group_id
  security_group_id        = aws_security_group.alb_internal[0].id
  description              = "Allow traffic to EKS NodePort HTTP"
}

# ============================================================================
# EKS Node Security Group Rules - Allow from ALBs
# ============================================================================

# Allow from Public ALB - HTTPS
resource "aws_security_group_rule" "eks_from_public_alb_https" {
  count = local.create_internet_facing ? 1 : 0
  
  type                     = "ingress"
  from_port                = var.https_nodeport
  to_port                  = var.https_nodeport
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public[0].id
  security_group_id        = var.eks_node_security_group_id
  description              = "Allow NodePort HTTPS from Public ALB"
}

# Allow from Public ALB - HTTP
resource "aws_security_group_rule" "eks_from_public_alb_http" {
  count = local.create_internet_facing ? 1 : 0
  
  type                     = "ingress"
  from_port                = var.http_nodeport
  to_port                  = var.http_nodeport
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public[0].id
  security_group_id        = var.eks_node_security_group_id
  description              = "Allow NodePort HTTP from Public ALB"
}

# Allow from Internal ALB - HTTPS
resource "aws_security_group_rule" "eks_from_internal_alb_https" {
  count = local.create_internal ? 1 : 0
  
  type                     = "ingress"
  from_port                = var.https_nodeport
  to_port                  = var.https_nodeport
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_internal[0].id
  security_group_id        = var.eks_node_security_group_id
  description              = "Allow NodePort HTTPS from Internal ALB"
}

# Allow from Internal ALB - HTTP
resource "aws_security_group_rule" "eks_from_internal_alb_http" {
  count = local.create_internal ? 1 : 0
  
  type                     = "ingress"
  from_port                = var.http_nodeport
  to_port                  = var.http_nodeport
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_internal[0].id
  security_group_id        = var.eks_node_security_group_id
  description              = "Allow NodePort HTTP from Internal ALB"
}

# ============================================================================
# WAF Web ACL Association (Optional)
# ============================================================================

resource "aws_wafv2_web_acl_association" "public_alb" {
  # count = local.create_internet_facing && var.waf_acl_arn != null ? 1 : 0
  count = local.create_internet_facing && var.enable_waf ? 1 : 0

  
  resource_arn = aws_lb.internet_facing[0].arn
  web_acl_arn  = var.waf_acl_arn
}
