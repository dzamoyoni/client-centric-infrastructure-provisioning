# ============================================================================
# Tagging Module Variables - Enterprise Standards
# ============================================================================
# Comprehensive variable definitions for scalable, consistent tagging
# across all infrastructure layers and environments
# ============================================================================

# ============================================================================
# Core Organizational Variables (Required)
# ============================================================================

variable "project_name" {
  description = "Name of the project (DEPRECATED - use client_name for client-centric architecture)"
  type        = string
  default     = ""
  validation {
    condition     = var.project_name == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9-_]*[A-Za-z0-9]$", var.project_name))
    error_message = "Project name must start and end with alphanumeric characters and can contain hyphens and underscores."
  }
}

variable "environment" {
  description = "Environment name (production, staging, development, test)"
  type        = string
  validation {
    condition     = contains(["production", "staging", "development", "test", "sandbox", "demo"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test, sandbox, demo."
  }
}

variable "layer_name" {
  description = "Infrastructure layer name (foundation, platform, database, observability, etc.)"
  type        = string
  validation {
    condition = contains([
      "foundation", "platform", "database", "observability", "application", 
      "security", "networking", "compute", "storage", "shared-services",
      "client-nodegroups", "standalone-compute", "database-layer"
    ], var.layer_name)
    error_message = "Layer name must be a valid infrastructure layer."
  }
}

variable "region" {
  description = "AWS region (required)"
  type        = string
  validation {
    condition     = var.region != ""
    error_message = "Region must be specified (cannot be empty)."
  }
}

# ============================================================================
# Organizational Metadata
# ============================================================================

variable "organization_name" {
  description = "Organization name"
  type        = string
  default     = "EZ"
}

variable "portfolio_name" {
  description = "Portfolio or program name"
  type        = string
  default     = "Tenant-EKS"
}

variable "business_unit" {
  description = "Business unit or division"
  type        = string
  default     = "Infrastructure"
}

variable "cost_center" {
  description = "Cost center for billing and chargeback"
  type        = string
  default     = "IT-Infrastructure"
}

variable "owner" {
  description = "Owner or responsible team"
  type        = string
  default     = "Platform-Engineering"
}

variable "contact_email" {
  description = "Contact email for this infrastructure"
  type        = string
  default     = "dennis.juma00@gmail.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.contact_email)) || var.contact_email == ""
    error_message = "Contact email must be a valid email address."
  }
}

# ============================================================================
# Infrastructure Metadata
# ============================================================================

variable "terraform_module" {
  description = "Terraform module path or name"
  type        = string
  default     = ""
}

variable "provisioned_by" {
  description = "Who or what provisioned this infrastructure"
  type        = string
  default     = "Terraform"
}

variable "account_id" {
  description = "AWS account ID (required for infrastructure tags)"
  type        = string
  default     = ""
}

variable "account_alias" {
  description = "AWS account alias"
  type        = string
  default     = ""
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = null
}

# ============================================================================
# Environment and Deployment Metadata
# ============================================================================

variable "environment_type" {
  description = "Type of environment (production, non-production, development)"
  type        = string
  default     = ""
  validation {
    condition = var.environment_type == "" || contains([
      "production", "non-production", "development", "testing", "staging"
    ], var.environment_type)
    error_message = "Environment type must be a valid environment classification."
  }
}

variable "layer_purpose" {
  description = "Purpose or description of this layer"
  type        = string
  default     = ""
}

variable "deployment_phase" {
  description = "Deployment phase (e.g., Phase-1, Phase-2)"
  type        = string
  default     = ""
}

variable "deployment_method" {
  description = "Method used for deployment"
  type        = string
  default     = "Terraform"
}

variable "deployment_date" {
  description = "Deployment date (YYYY-MM-DD format, auto-generated if empty)"
  type        = string
  default     = ""
}

variable "infrastructure_version" {
  description = "Version of the infrastructure or application"
  type        = string
  default     = ""
}

# ============================================================================
# Operational Metadata
# ============================================================================

variable "critical_infrastructure" {
  description = "Whether this is critical infrastructure"
  type        = string
  default     = "true"
  validation {
    condition     = contains(["true", "false", "high", "medium", "low"], var.critical_infrastructure)
    error_message = "Critical infrastructure must be true, false, high, medium, or low."
  }
}

variable "backup_required" {
  description = "Whether backup is required"
  type        = string
  default     = "true"
  validation {
    condition     = contains(["true", "false", "daily", "weekly", "monthly"], var.backup_required)
    error_message = "Backup required must be true, false, daily, weekly, or monthly."
  }
}

variable "security_level" {
  description = "Security level classification"
  type        = string
  default     = "High"
  validation {
    condition     = contains(["Low", "Medium", "High", "Critical"], var.security_level)
    error_message = "Security level must be Low, Medium, High, or Critical."
  }
}

variable "compliance_level" {
  description = "Compliance level or framework"
  type        = string
  default     = "Standard"
}

variable "data_classification" {
  description = "Data classification level"
  type        = string
  default     = "Internal"
  validation {
    condition = contains([
      "Public", "Internal", "Confidential", "Restricted", "Secret"
    ], var.data_classification)
    error_message = "Data classification must be Public, Internal, Confidential, Restricted, or Secret."
  }
}

variable "maintenance_window" {
  description = "Maintenance window"
  type        = string
  default     = "Sunday-02:00-04:00-UTC"
}

variable "sla_tier" {
  description = "SLA tier (Gold, Silver, Bronze)"
  type        = string
  default     = "Silver"
  validation {
    condition     = contains(["Bronze", "Silver", "Gold", "Platinum"], var.sla_tier)
    error_message = "SLA tier must be Bronze, Silver, Gold, or Platinum."
  }
}

variable "monitoring_level" {
  description = "Level of monitoring required"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Enhanced", "Premium"], var.monitoring_level)
    error_message = "Monitoring level must be Basic, Standard, Enhanced, or Premium."
  }
}

# ============================================================================
# Cost Management Variables
# ============================================================================

variable "billing_group" {
  description = "Billing group for cost allocation"
  type        = string
  default     = ""
}

variable "chargeback_code" {
  description = "Chargeback code for internal billing"
  type        = string
  default     = ""
}

variable "budget_name" {
  description = "Associated budget name"
  type        = string
  default     = ""
}

variable "cost_optimization_enabled" {
  description = "Whether cost optimization is enabled"
  type        = string
  default     = "true"
  validation {
    condition     = contains(["true", "false"], var.cost_optimization_enabled)
    error_message = "Cost optimization enabled must be true or false."
  }
}

variable "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled"
  type        = string
  default     = "true"
  validation {
    condition     = contains(["true", "false"], var.auto_scaling_enabled)
    error_message = "Auto scaling enabled must be true or false."
  }
}

variable "instance_schedule" {
  description = "Instance scheduling (always-on, business-hours, custom)"
  type        = string
  default     = "always-on"
}

# ============================================================================
# Client/Tenant Variables (Multi-tenant support)
# ============================================================================

variable "client_name" {
  description = "Client name for multi-tenant environments"
  type        = string
  default     = ""
}

variable "client_code" {
  description = "Client code or abbreviation"
  type        = string
  default     = ""
}

variable "client_tier" {
  description = "Client tier (premium, standard, basic)"
  type        = string
  default     = ""
}

variable "client_region" {
  description = "Client's primary region"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Tenant identifier"
  type        = string
  default     = ""
}

variable "service_level" {
  description = "Service level for this client"
  type        = string
  default     = ""
}

# ============================================================================
# Application Variables
# ============================================================================

variable "application_name" {
  description = "Application name"
  type        = string
  default     = ""
}

variable "application_version" {
  description = "Application version"
  type        = string
  default     = ""
}

variable "application_owner" {
  description = "Application owner or team"
  type        = string
  default     = ""
}

variable "application_tier" {
  description = "Application tier (frontend, backend, database)"
  type        = string
  default     = ""
}

variable "service_name" {
  description = "Service name"
  type        = string
  default     = ""
}

variable "component_name" {
  description = "Component name"
  type        = string
  default     = ""
}

# ============================================================================
# Governance and Compliance Variables
# ============================================================================

variable "created_by" {
  description = "Who created this infrastructure"
  type        = string
  default     = "Terraform"
}

variable "creation_date" {
  description = "Creation date (YYYY-MM-DD format, auto-generated if empty)"
  type        = string
  default     = ""
}

variable "change_ticket" {
  description = "Change ticket or request number"
  type        = string
  default     = ""
}

variable "compliance_framework" {
  description = "Compliance framework (SOC2, ISO27001, PCI-DSS, etc.)"
  type        = string
  default     = ""
}

variable "data_retention" {
  description = "Data retention period"
  type        = string
  default     = ""
}

variable "archive_policy" {
  description = "Archive policy"
  type        = string
  default     = ""
}

# ============================================================================
# Layer-Specific Variables
# ============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version (for platform layer)"
  type        = string
  default     = ""
}

variable "database_engine" {
  description = "Database engine (for database layer)"
  type        = string
  default     = ""
}

variable "backup_strategy" {
  description = "Backup strategy (for database layer)"
  type        = string
  default     = ""
}

# ============================================================================
# Custom Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional custom tags to merge with standard tags"
  type        = map(string)
  default     = {}
}