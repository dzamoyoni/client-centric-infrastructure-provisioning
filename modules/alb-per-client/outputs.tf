# ============================================================================
# Internet-Facing ALB Outputs
# ============================================================================

output "public_alb_id" {
  description = "ID of the internet-facing ALB"
  value       = try(aws_lb.internet_facing[0].id, null)
}

output "public_alb_arn" {
  description = "ARN of the internet-facing ALB"
  value       = try(aws_lb.internet_facing[0].arn, null)
}

output "public_alb_dns_name" {
  description = "DNS name of the internet-facing ALB"
  value       = try(aws_lb.internet_facing[0].dns_name, null)
}

output "public_alb_zone_id" {
  description = "Route53 Zone ID of the internet-facing ALB"
  value       = try(aws_lb.internet_facing[0].zone_id, null)
}

output "public_alb_security_group_id" {
  description = "Security group ID of the internet-facing ALB"
  value       = try(aws_security_group.alb_public[0].id, null)
}

# ============================================================================
# Internal ALB Outputs
# ============================================================================

output "internal_alb_id" {
  description = "ID of the internal ALB"
  value       = try(aws_lb.internal[0].id, null)
}

output "internal_alb_arn" {
  description = "ARN of the internal ALB"
  value       = try(aws_lb.internal[0].arn, null)
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB"
  value       = try(aws_lb.internal[0].dns_name, null)
}

output "internal_alb_zone_id" {
  description = "Route53 Zone ID of the internal ALB"
  value       = try(aws_lb.internal[0].zone_id, null)
}

output "internal_alb_security_group_id" {
  description = "Security group ID of the internal ALB"
  value       = try(aws_security_group.alb_internal[0].id, null)
}

# ============================================================================
# Target Group Outputs - Public
# ============================================================================

output "public_https_target_group_arn" {
  description = "ARN of the public HTTPS target group"
  value       = try(aws_lb_target_group.https_public[0].arn, null)
}

output "public_https_target_group_name" {
  description = "Name of the public HTTPS target group"
  value       = try(aws_lb_target_group.https_public[0].name, null)
}

output "public_http_target_group_arn" {
  description = "ARN of the public HTTP target group"
  value       = try(aws_lb_target_group.http_public[0].arn, null)
}

output "public_http_target_group_name" {
  description = "Name of the public HTTP target group"
  value       = try(aws_lb_target_group.http_public[0].name, null)
}

# ============================================================================
# Target Group Outputs - Internal
# ============================================================================

output "internal_https_target_group_arn" {
  description = "ARN of the internal HTTPS target group"
  value       = try(aws_lb_target_group.https_internal[0].arn, null)
}

output "internal_https_target_group_name" {
  description = "Name of the internal HTTPS target group"
  value       = try(aws_lb_target_group.https_internal[0].name, null)
}

output "internal_http_target_group_arn" {
  description = "ARN of the internal HTTP target group"
  value       = try(aws_lb_target_group.http_internal[0].arn, null)
}

output "internal_http_target_group_name" {
  description = "Name of the internal HTTP target group"
  value       = try(aws_lb_target_group.http_internal[0].name, null)
}

# ============================================================================
# Listener Outputs - Public
# ============================================================================

output "public_https_listener_arn" {
  description = "ARN of the public HTTPS listener"
  value       = try(aws_lb_listener.public_https[0].arn, null)
}

output "public_http_listener_arn" {
  description = "ARN of the public HTTP listener"
  value       = try(aws_lb_listener.public_http[0].arn, null)
}

# ============================================================================
# Listener Outputs - Internal
# ============================================================================

output "internal_https_listener_arn" {
  description = "ARN of the internal HTTPS listener"
  value       = try(aws_lb_listener.internal_https[0].arn, null)
}

output "internal_http_listener_arn" {
  description = "ARN of the internal HTTP listener"
  value       = try(aws_lb_listener.internal_http[0].arn, null)
}

# ============================================================================
# Convenience Outputs
# ============================================================================

output "alb_endpoints" {
  description = "Map of ALB endpoints for easy reference"
  value = {
    public = {
      https = try("https://${aws_lb.internet_facing[0].dns_name}:${var.https_external_port}", null)
      http  = try("http://${aws_lb.internet_facing[0].dns_name}:${var.http_external_port}", null)
    }
    internal = {
      https = try("https://${aws_lb.internal[0].dns_name}:${var.https_external_port}", null)
      http  = try("http://${aws_lb.internal[0].dns_name}:${var.http_external_port}", null)
    }
  }
}

output "target_group_arns" {
  description = "All target group ARNs for attaching to EKS Auto Scaling Groups"
  value = compact([
    try(aws_lb_target_group.https_public[0].arn, ""),
    try(aws_lb_target_group.http_public[0].arn, ""),
    try(aws_lb_target_group.https_internal[0].arn, ""),
    try(aws_lb_target_group.http_internal[0].arn, ""),
  ])
}

output "alb_configuration_summary" {
  description = "Summary of ALB configuration for documentation"
  value = {
    client_id                 = var.client_id
    environment               = var.environment
    alb_type                  = var.alb_type
    public_alb_created        = try(aws_lb.internet_facing[0].id, null) != null
    internal_alb_created      = try(aws_lb.internal[0].id, null) != null
    https_external_port       = var.https_external_port
    http_external_port        = var.http_external_port
    https_nodeport            = var.https_nodeport
    http_nodeport             = var.http_nodeport
    redirect_http_to_https    = var.redirect_http_to_https
    ssl_policy                = var.ssl_policy
    deletion_protection       = var.enable_deletion_protection
    access_logs_enabled       = var.enable_access_logs
    waf_enabled               = var.waf_acl_arn != null
    sticky_sessions_enabled   = var.enable_sticky_sessions
  }
}
