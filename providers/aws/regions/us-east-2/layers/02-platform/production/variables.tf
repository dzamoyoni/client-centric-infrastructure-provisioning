# Platform Layer Variables
# Per-Client EKS Clusters — Each client gets a dedicated cluster in their VPC
#
# TYPE CONTRACT: This file must mirror the COMPLETE shape of clients.auto.tfvars.
# Terraform validates the full object on every plan. Blocks unused by this layer
# are declared optional(object, null) and accessed via try() in main.tf / dns.tf.
#
# DEFAULT PATTERN:
#   optional(object({...}), null)   ← correct for complex optional objects
#   try(config.block.field, false)  ← safe access in main.tf wherever block may be null
#
# Do NOT use bare object literals as defaults e.g. { enabled = false }.
# Terraform cannot coerce a bare map literal to a typed object at the default level.

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform remote state"
  type        = string
}

variable "terraform_state_region" {
  description = "AWS region of the Terraform state bucket"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for all EKS clusters in this layer"
  type        = string
}

variable "enable_public_access" {
  description = "Enable public access to the EKS API endpoint"
  type        = bool
}

variable "management_cidr_blocks" {
  description = "CIDR blocks permitted to reach the EKS API endpoint"
  type        = list(string)
}

# ==============================================================================
# clients — Single Source of Truth
# ==============================================================================
# Loaded from ROOT /clients.auto.tfvars via Terraform's auto-loading.
# The type below must exactly match the shape written in that file.
# Layers that don't consume a block (e.g. Layer 02 ignores `database`) still
# must declare it so Terraform accepts the shared tfvars without type errors.

variable "clients" {
  description = "Per-client configuration map. Single source of truth in ROOT /clients.auto.tfvars."
  type = map(object({
    enabled     = bool
    client_code = string
    tier        = string

    # --------------------------------------------------------------------------
    # NETWORK — consumed by Layer 01 (Foundation). Passthrough for other layers.
    # --------------------------------------------------------------------------
    network = optional(object({
      vpc_cidr = optional(string, "")
    }), null)

    # --------------------------------------------------------------------------
    # SECURITY — consumed by Layer 01 (Foundation).
    # --------------------------------------------------------------------------
    security = optional(object({
      custom_ports   = optional(list(number), [])
      database_ports = optional(list(number), [])
    }), null)

    # --------------------------------------------------------------------------
    # VPN — consumed by Layer 01 (Foundation).
    # --------------------------------------------------------------------------
    vpn = optional(object({
      enabled             = optional(bool, false)
      customer_gateway_ip = optional(string, "")
      bgp_asn             = optional(number, 0)
      amazon_side_asn     = optional(number, 0)
      local_network_cidr  = optional(string, "")
      tunnel1_inside_cidr = optional(string, "")
      tunnel2_inside_cidr = optional(string, "")
      static_routes_only  = optional(bool, false)
      description         = optional(string, "")
    }), null)

    # --------------------------------------------------------------------------
    # EKS — primary resource created by THIS layer (Layer 02: Platform).
    # Required (not optional) because every client record must declare it.
    # --------------------------------------------------------------------------
    eks = object({
      enabled        = bool
      instance_types = list(string)
      min_size       = number
      max_size       = number
      desired_size   = number
      disk_size      = number
      capacity_type  = string # "ON_DEMAND" | "SPOT"
    })

    # --------------------------------------------------------------------------
    # ALB — created by THIS layer. null default: always access via try() in main.tf.
    # --------------------------------------------------------------------------
    alb = optional(object({
      enabled    = optional(bool, false)
      type       = optional(string, "internal") # "internet-facing" | "internal" | "both"

      https_external_port = optional(number, 443)
      http_external_port  = optional(number, 80)
      https_nodeport      = optional(number, 30443)
      http_nodeport       = optional(number, 30080)

      ssl_certificate_arn          = optional(string, "")
      ssl_certificate_arn_internal = optional(string, "")
      ssl_policy                   = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
      redirect_http_to_https       = optional(bool, true)

      allowed_cidr_blocks_public   = optional(list(string), [])
      allowed_cidr_blocks_internal = optional(list(string), [])

      health_check_path = optional(string, "/health")

      enable_access_logs         = optional(bool, false)
      enable_waf                 = optional(bool, false)
      enable_deletion_protection = optional(bool, false)
      enable_sticky_sessions     = optional(bool, false)
    }), null)

    # --------------------------------------------------------------------------
    # DNS — consumed by THIS layer (dns.tf). null default: access via try().
    # --------------------------------------------------------------------------
    dns = optional(object({
      enabled                  = optional(bool, false)
      domain_name              = optional(string, "")
      public_subdomain         = optional(string, "app")
      internal_subdomain       = optional(string, "internal")
      create_route53_records   = optional(bool, false)
      create_wildcard_record   = optional(bool, false)
      evaluate_target_health   = optional(bool, true)
      private_zone_domain_name = optional(string, "")
    }), null)

    # --------------------------------------------------------------------------
    # DATABASE — consumed by Layer 03. Passthrough for this layer.
    # --------------------------------------------------------------------------
    database = optional(object({
      enabled            = optional(bool, false)
      instance_type      = optional(string, "")
      data_volume_size   = optional(number, 50)
      wal_volume_size    = optional(number, 25)
      backup_volume_size = optional(number, 50)
      enable_replica     = optional(bool, false)
    }), null)

    # --------------------------------------------------------------------------
    # COMPUTE — consumed by Layer 04. Passthrough for this layer.
    # --------------------------------------------------------------------------
    compute = optional(object({
      enabled        = optional(bool, false)
      instance_type  = optional(string, "")
      instance_count = optional(number, 0)
    }), null)

    # --------------------------------------------------------------------------
    # METADATA — used across ALL layers for tagging and cost allocation.
    # --------------------------------------------------------------------------
    metadata = object({
      full_name     = string
      industry      = string
      contact_email = string
      compliance    = list(string)
      cost_center   = string
      business_unit = string
    })
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, c in var.clients :
      contains(["ON_DEMAND", "SPOT"], c.eks.capacity_type)
      if c.enabled && c.eks.enabled
    ])
    error_message = "eks.capacity_type must be 'ON_DEMAND' or 'SPOT'."
  }

  validation {
    condition = alltrue([
      for name, c in var.clients :
      c.eks.min_size <= c.eks.desired_size && c.eks.desired_size <= c.eks.max_size
      if c.enabled && c.eks.enabled
    ])
    error_message = "eks.min_size <= eks.desired_size <= eks.max_size must hold for all enabled clients."
  }

  validation {
    condition = alltrue([
      for name, c in var.clients :
      c.eks.disk_size >= 20 && c.eks.disk_size <= 1000
      if c.enabled && c.eks.enabled
    ])
    error_message = "eks.disk_size must be between 20 and 1000 GB."
  }

  validation {
    condition = alltrue([
      for name, c in var.clients :
      contains(["internet-facing", "internal", "both"], try(c.alb.type, "internal"))
      if c.enabled && try(c.alb.enabled, false)
    ])
    error_message = "alb.type must be 'internet-facing', 'internal', or 'both'."
  }
}
