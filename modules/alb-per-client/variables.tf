# ============================================================================
# Required Variables
# ============================================================================

variable "client_id" {
  description = "Unique identifier for the client (e.g., client-a, client-b)"
  type        = string

  validation {
    condition     = length(var.client_id) >= 2 && length(var.client_id) <= 12
    error_message = "client_id must be between 2 and 12 characters to keep ALB names within AWS's 32-character limit."
  }

  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client_id))
    error_message = "Client ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development", "dr"], var.environment)
    error_message = "Environment must be one of: production, staging, development, dr."
  }
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must only contain lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for internet-facing ALB"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for internal ALB"
  type        = list(string)
  default     = []
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listeners (AWS Certificate Manager)"
  type        = string
}

# ============================================================================
# ALB Configuration
# ============================================================================

variable "alb_type" {
  description = "Type of ALB to create: 'internet-facing', 'internal', or 'both'"
  type        = string
  default     = "both"
  
  validation {
    condition     = contains(["internet-facing", "internal", "both"], var.alb_type)
    error_message = "ALB type must be one of: internet-facing, internal, both."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALBs (recommended for production)"
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
  default     = ""
}

# ============================================================================
# Port Configuration
# ============================================================================

variable "https_external_port" {
  description = "External HTTPS port that ALB listens on"
  type        = number
  default     = 30443
  
  validation {
    condition     = var.https_external_port > 0 && var.https_external_port <= 65535
    error_message = "HTTPS external port must be between 1 and 65535."
  }
}

variable "http_external_port" {
  description = "External HTTP port that ALB listens on"
  type        = number
  default     = 30080
  
  validation {
    condition     = var.http_external_port > 0 && var.http_external_port <= 65535
    error_message = "HTTP external port must be between 1 and 65535."
  }
}

variable "https_nodeport" {
  description = "NodePort on EKS nodes for HTTPS traffic (matches Istio Ingress Gateway NodePort)"
  type        = number
  default     = 30443
  
  validation {
    condition     = var.https_nodeport >= 30000 && var.https_nodeport <= 32767
    error_message = "HTTPS NodePort must be in the Kubernetes NodePort range (30000-32767)."
  }
}

variable "http_nodeport" {
  description = "NodePort on EKS nodes for HTTP traffic (matches Istio Ingress Gateway NodePort)"
  type        = number
  default     = 30080
  
  validation {
    condition     = var.http_nodeport >= 30000 && var.http_nodeport <= 32767
    error_message = "HTTP NodePort must be in the Kubernetes NodePort range (30000-32767)."
  }
}

variable "redirect_http_to_https" {
  description = "Redirect HTTP traffic to HTTPS (recommended for production)"
  type        = bool
  default     = true
}

# ============================================================================
# SSL/TLS Configuration
# ============================================================================

variable "ssl_policy" {
  description = "SSL policy for HTTPS listeners (AWS predefined security policy)"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  
  validation {
    condition = contains([
      "ELBSecurityPolicy-TLS13-1-2-2021-06",
      "ELBSecurityPolicy-TLS-1-2-2017-01",
      "ELBSecurityPolicy-TLS-1-2-Ext-2018-06",
      "ELBSecurityPolicy-FS-1-2-Res-2020-10"
    ], var.ssl_policy)
    error_message = "SSL policy must be a valid AWS ELB security policy."
  }
}

variable "ssl_certificate_arn_internal" {
  description = "Optional: Separate SSL certificate ARN for internal ALB (defaults to ssl_certificate_arn if not provided)"
  type        = string
  default     = null
}

# ============================================================================
# Health Check Configuration
# ============================================================================

variable "health_check_path" {
  description = "Path for health checks (must be exposed by Istio Ingress Gateway)"
  type        = string
  default     = "/healthz/ready"
  
  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "Health check path must start with /."
  }
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "allowed_cidr_blocks_public" {
  description = "CIDR blocks allowed to access the public ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_cidr_blocks_internal" {
  description = "CIDR blocks allowed to access the internal ALB (e.g., VPN, corporate network)"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "enable_waf" {
  description = "Whether to associate a WAF ACL with the public ALB"
  type        = bool
  default     = false
}

variable "waf_acl_arn" {
  description = "ARN of AWS WAF Web ACL to associate with public ALB. Required when enable_waf = true."
  type        = string
  default     = null

  validation {
    condition     = var.waf_acl_arn == null || can(regex("^arn:", var.waf_acl_arn))
    error_message = "waf_acl_arn must be a valid ARN or null."
  }
}



# ============================================================================
# Session Configuration
# ============================================================================

variable "enable_sticky_sessions" {
  description = "Enable sticky sessions (session affinity) using ALB cookies"
  type        = bool
  default     = false
}

# ============================================================================
# Tagging
# ============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources (merged with common tags)"
  type        = map(string)
  default     = {}
}
