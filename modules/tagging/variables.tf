# ============================================================================
# Tagging Module Variables
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
      "bootstrap", "foundation", "transit", "platform", "database", "observability", "application", 
      "security", "networking", "compute", "storage", "shared-services",
      "client-nodegroups", "standalone-compute", "database-layer", "cluster-services"
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

variable "terraform_version" {
  description = "Terraform version used for deployment (for automation tracking)"
  type        = string
  default     = ""
}

variable "provisioned_by" {
  description = "Who or what provisioned this infrastructure"
  type        = string
  default     = "Terraform"
}

variable "deployment_pipeline" {
  description = "CI/CD pipeline or system that deployed this (e.g., GitHub Actions, GitLab CI, Jenkins)"
  type        = string
  default     = ""
}

variable "git_commit" {
  description = "Git commit SHA that deployed this infrastructure (for version tracking)"
  type        = string
  default     = ""
  validation {
    condition     = var.git_commit == "" || can(regex("^[a-f0-9]{7,40}$", var.git_commit))
    error_message = "Git commit must be a valid SHA (7-40 hex characters) or empty."
  }
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
  description = "Deployment date (YYYY-MM-DD or RFC3339 format). Must be provided externally - no auto-generation to prevent state churn"
  type        = string
  default     = ""
  validation {
    condition     = var.deployment_date == "" || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}", var.deployment_date))
    error_message = "Deployment date must be in YYYY-MM-DD format or empty."
  }
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

variable "encryption_required" {
  description = "Whether encryption is required for this resource (true/false)"
  type        = string
  default     = "true"
  validation {
    condition     = contains(["true", "false"], var.encryption_required)
    error_message = "Encryption required must be true or false."
  }
}

variable "data_residency" {
  description = "Data residency requirement (region or country where data must reside)"
  type        = string
  default     = ""
}

variable "dr_tier" {
  description = "Disaster Recovery tier (Tier-1: Mission Critical, Tier-2: Business Critical, Tier-3: Important, Tier-4: Non-Critical)"
  type        = string
  default     = "Tier-3"
  validation {
    condition     = var.dr_tier == "" || contains(["Tier-1", "Tier-2", "Tier-3", "Tier-4"], var.dr_tier)
    error_message = "DR tier must be Tier-1, Tier-2, Tier-3, or Tier-4."
  }
}

variable "rpo" {
  description = "Recovery Point Objective (maximum acceptable data loss period, e.g., 1h, 4h, 24h)"
  type        = string
  default     = "24h"
}

variable "rto" {
  description = "Recovery Time Objective (maximum acceptable downtime, e.g., 1h, 4h, 24h)"
  type        = string
  default     = "24h"
}

variable "patch_group" {
  description = "Patch group for automated patching schedules (e.g., Group-A, Group-B, Critical, Non-Critical)"
  type        = string
  default     = "Standard"
}

variable "runbook_url" {
  description = "URL to operational runbook or documentation for this resource"
  type        = string
  default     = ""
  validation {
    condition     = var.runbook_url == "" || can(regex("^https?://", var.runbook_url))
    error_message = "Runbook URL must be a valid HTTP/HTTPS URL or empty."
  }
}

variable "incident_contact" {
  description = "Incident contact (email, Slack channel, PagerDuty, or phone for operational alerts)"
  type        = string
  default     = ""
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

variable "resource_type" {
  description = "Type of AWS resource (EC2, RDS, EKS, S3, Lambda, etc.) for cost allocation and filtering"
  type        = string
  default     = ""
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
  description = "Creation date (YYYY-MM-DD format). Must be provided externally - no auto-generation to prevent state churn"
  type        = string
  default     = ""
  validation {
    condition     = var.creation_date == "" || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}", var.creation_date))
    error_message = "Creation date must be in YYYY-MM-DD format or empty."
  }
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

variable "layer_specific_tags" {
  description = "Custom layer-specific tags to merge with default layer tags (extensible)"
  type        = map(string)
  default     = {}
}
