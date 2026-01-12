# ============================================================================
# Centralized Tagging Module - Enterprise Standards
# ============================================================================
# This module provides consistent, scalable tagging across all infrastructure
# layers with support for:
# - Standardized organizational tags
# - Environment-specific tags  
# - Layer-specific tags
# - Cost allocation tags
# - Compliance tags
# - Client/tenant-specific tags
# ============================================================================

terraform {
  required_version = ">= 1.5"
}

# ============================================================================
# Note: No data sources to avoid circular dependencies with AWS provider
# Dynamic values are passed as variables or computed in calling module
# ============================================================================

# ============================================================================
# Local Tag Logic
# ============================================================================

locals {
  # Sanitize tag values to ensure AWS compliance
  # Remove commas, limit length, ensure valid characters
  # Use client_name if project_name is empty (client-centric architecture)
  effective_project_name = var.project_name != "" ? var.project_name : (var.client_name != "" ? var.client_name : "${var.region}-${var.environment}")
  
  sanitize_value = {
    for k, v in {
      organization_name    = var.organization_name
      project_name        = local.effective_project_name
      portfolio_name      = var.portfolio_name
      business_unit       = var.business_unit
      cost_center         = var.cost_center
      owner              = var.owner
      contact_email      = var.contact_email
      layer_purpose      = var.layer_purpose
      deployment_phase   = var.deployment_phase
      deployment_method  = var.deployment_method
      chargeback_code    = var.chargeback_code
      compliance_framework = var.compliance_framework
    } : k => v != null ? substr(replace(replace(v, ",", "-"), "  ", " "), 0, 255) : ""
  }

  # Standard organizational metadata
  organization_tags = {
    Organization    = local.sanitize_value["organization_name"]
    Project         = local.sanitize_value["project_name"]
    Portfolio       = local.sanitize_value["portfolio_name"]
    BusinessUnit    = local.sanitize_value["business_unit"]
    CostCenter      = local.sanitize_value["cost_center"]
    Owner           = local.sanitize_value["owner"]
    ContactEmail    = local.sanitize_value["contact_email"]
  }

  # Infrastructure metadata (account_id omitted to avoid circular dependencies)
  infrastructure_tags = {
    ManagedBy           = "Terraform"
    TerraformModule     = var.terraform_module
    TerraformWorkspace  = terraform.workspace
    ProvisionedBy       = var.provisioned_by
    Region              = var.region
    AvailabilityZones   = var.availability_zones != null ? join(",", var.availability_zones) : ""
    AccountAlias        = var.account_alias
  }

  # Environment and deployment metadata
  environment_tags = {
    Environment         = var.environment
    EnvironmentType     = var.environment_type
    Layer               = var.layer_name
    LayerPurpose        = local.sanitize_value["layer_purpose"]
    DeploymentPhase     = local.sanitize_value["deployment_phase"]
    DeploymentMethod    = local.sanitize_value["deployment_method"]
    DeploymentDate      = var.deployment_date != "" ? var.deployment_date : formatdate("YYYY-MM-DD", timestamp())
    Version             = var.infrastructure_version
  }

  # Operational metadata
  operational_tags = {
    CriticalInfra       = var.critical_infrastructure
    BackupRequired      = var.backup_required
    SecurityLevel       = var.security_level
    ComplianceLevel     = var.compliance_level
    DataClassification  = var.data_classification
    MaintenanceWindow   = var.maintenance_window
    SLA                 = var.sla_tier
    MonitoringLevel     = var.monitoring_level
  }

  # Cost management tags
  cost_tags = {
    BillingGroup        = local.sanitize_value["owner"]
    ChargebackCode      = local.sanitize_value["chargeback_code"]
    Budget              = var.budget_name
    CostOptimization    = var.cost_optimization_enabled
    AutoScalingEnabled  = var.auto_scaling_enabled
    InstanceSchedule    = var.instance_schedule
  }

  # Client/tenant-specific tags (for multi-tenant environments)
  client_tags = var.client_name != "" ? {
    Client              = var.client_name
    ClientCode          = var.client_code
    ClientTier          = var.client_tier
    ClientRegion        = var.client_region
    TenantId            = var.tenant_id
    ServiceLevel        = var.service_level
  } : {}

  # Application-specific tags
  application_tags = var.application_name != "" ? {
    ApplicationName     = var.application_name
    ApplicationVersion  = var.application_version
    ApplicationOwner    = var.application_owner
    ApplicationTier     = var.application_tier
    ServiceName         = var.service_name
    ComponentName       = var.component_name
  } : {}

  # Compliance and governance tags
  governance_tags = {
    CreatedBy           = var.created_by
    CreationDate        = var.creation_date != "" ? var.creation_date : formatdate("YYYY-MM-DD", timestamp())
    LastModified        = formatdate("YYYY-MM-DD", timestamp())
    ChangeTicket        = var.change_ticket
    ComplianceFramework = local.sanitize_value["compliance_framework"]
    DataRetention       = var.data_retention
    ArchivePolicy       = var.archive_policy
  }

  # Merge all tag categories, removing empty values
  all_tags = merge(
    local.organization_tags,
    local.infrastructure_tags,
    local.environment_tags,
    local.operational_tags,
    local.cost_tags,
    local.client_tags,
    local.application_tags,
    local.governance_tags,
    var.additional_tags
  )

  # Filter out empty values and null values
  filtered_tags = {
    for k, v in local.all_tags : k => v
    if v != null && v != ""
  }

  # Create layer-specific tag variations
  layer_specific_tags = merge(
    local.filtered_tags,
    var.layer_name == "foundation" ? {
      NetworkTier       = "Foundation"
      VPCPurpose        = "Tenant-EKS"
      NATConfiguration  = "HighAvailability"
    } : {},
    var.layer_name == "platform" ? {
      ClusterRole       = "Primary"
      KubernetesVersion = var.kubernetes_version
      NodeGroupType     = "Mixed"
    } : {},
    var.layer_name == "observability" ? {
      ObservabilityStack = "FluentBit-Tempo-Prometheus"
      LoggingEnabled     = "true"
      TracingEnabled     = "true"
      MetricsEnabled     = "true"
    } : {},
    var.layer_name == "database" ? {
      DatabaseEngine     = var.database_engine
      BackupStrategy     = var.backup_strategy
      EncryptionEnabled  = "true"
    } : {}
  )
}

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