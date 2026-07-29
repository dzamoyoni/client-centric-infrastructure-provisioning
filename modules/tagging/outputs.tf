# ============================================================================
# Outputs - Different tag combinations for different use cases
# ============================================================================

# Standard tags for most resources
output "standard_tags" {
  description = "Standard tags for most AWS resources"
  value       = local.layer_specific_tags
}

# Minimal tags for cost-sensitive resources
output "minimal_tags" {
  description = "Minimal essential tags for cost optimization"
  value = merge(
    {
      Project           = local.effective_project_name
      Environment       = var.environment
      ManagedBy         = "Terraform"
      Layer             = var.layer_name
      CostCenter        = var.cost_center
      Owner             = var.owner
    },
    var.client_name != "" ? { Client = var.client_name } : {}
  )
}

# Comprehensive tags for critical resources
output "comprehensive_tags" {
  description = "Comprehensive tags for critical infrastructure"
  value = merge(local.layer_specific_tags, {
    Backup            = "Critical"
    Security          = "Enhanced"
    Monitoring        = "24x7"
  })
}

# Client-specific tags for multi-tenant resources
output "client_tags" {
  description = "Client-specific tags for tenant environments"
  value       = merge(local.layer_specific_tags, local.client_tags)
}

# Tags formatted for Kubernetes labels (DNS-1123 compliant)
output "kubernetes_labels" {
  description = "Tags formatted as Kubernetes labels"
  value = {
    for k, v in local.layer_specific_tags :
    "tenant.io/${replace(lower(k), " ", "-")}" => replace(lower(v), " ", "-")
    if can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-_.]*[a-zA-Z0-9])?$", replace(lower(v), " ", "-")))
  }
}

# Raw tag components for custom merging
output "tag_components" {
  description = "Individual tag components for custom merging"
  value = {
    organization_tags   = local.organization_tags
    infrastructure_tags = local.infrastructure_tags
    environment_tags    = local.environment_tags
    operational_tags    = local.operational_tags
    cost_tags          = local.cost_tags
    client_tags        = local.client_tags
    application_tags   = local.application_tags
    governance_tags    = local.governance_tags
  }
}

# Summary information for validation
output "tag_summary" {
  description = "Summary of applied tags for validation"
  value = {
    total_tags        = length(local.layer_specific_tags)
    project          = var.project_name
    environment      = var.environment
    layer            = var.layer_name
    client           = var.client_name
    region           = var.region
    managed_by       = "Terraform"
    tag_categories   = ["organization", "infrastructure", "environment", "operational", "cost", "governance"]
    has_client_tags  = length(local.client_tags) > 0
    compliance_level = var.compliance_level
  }
}

# ============================================================================
# Enhanced Outputs for Industrial Standards
# ============================================================================

# Cost allocation tags (AWS Cost Explorer / FinOps)
output "cost_allocation_tags" {
  description = "Essential tags for AWS Cost Explorer and cost allocation"
  value = merge(
    {
      CostCenter  = var.cost_center
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
    },
    var.client_name != "" ? { Client = var.client_name } : {},
    var.application_name != "" ? { Application = var.application_name } : {}
  )
}

# Required tags for compliance validation
output "required_tags" {
  description = "Minimum required tags that must be present on all resources"
  value = {
    Environment = var.environment
    CostCenter  = var.cost_center
    Owner       = var.owner
    ManagedBy   = "Terraform"
    Layer       = var.layer_name
  }
}

# Tag compliance and validation status
output "tag_compliance" {
  description = "Tag compliance validation results"
  value = local.tag_validation
}

# Resource-type specific tags
output "resource_type_tags" {
  description = "Tags specific to resource type for filtering"
  value = var.resource_type != "" ? merge(
    local.layer_specific_tags,
    {
      ResourceType = var.resource_type
    }
  ) : local.layer_specific_tags
}

# Security and compliance tags
output "security_tags" {
  description = "Security-focused tags for TBAC (Tag-Based Access Control)"
  value = {
    SecurityLevel       = var.security_level
    DataClassification  = var.data_classification
    ComplianceFramework = var.compliance_framework
    EncryptionRequired  = var.encryption_required
    DataResidency       = var.data_residency
  }
}

# Operational tags for automation
output "operational_tags" {
  description = "Tags for operational automation and runbooks"
  value = {
    MaintenanceWindow = var.maintenance_window
    BackupRequired    = var.backup_required
    PatchGroup        = var.patch_group
    DRTier            = var.dr_tier
    RPO               = var.rpo
    RTO               = var.rto
    MonitoringLevel   = var.monitoring_level
    RunbookUrl        = var.runbook_url
    IncidentContact   = var.incident_contact
  }
}