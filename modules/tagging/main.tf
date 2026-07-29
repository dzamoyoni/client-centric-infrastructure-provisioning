# ============================================================================
# Centralized Tagging Module
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
  # AWS Tag Limits (Industrial Standards)
  aws_tag_limit         = 50  # AWS hard limit
  safe_tag_limit        = 45  # Safe limit with buffer
  tag_key_max_length    = 128 # AWS limit for tag keys
  tag_value_max_length  = 256 # AWS limit for tag values
  
  # Sanitize tag values to ensure AWS compliance
  # Remove commas, newlines, tabs, control characters, limit length, ensure valid characters
  # Use client_name if project_name is empty (client-centric architecture)
  effective_project_name = var.project_name != "" ? var.project_name : (var.client_name != "" ? var.client_name : "unknown")
  
  # Enhanced sanitization function for tag values
  # Removes: invalid characters (commas, semicolons, ampersands, etc.)
  # Replaces: spaces, slashes, colons with hyphens
  # Limits: 256 characters (AWS limit)
  # AWS allows: letters, numbers, spaces, and + - = . _ : / @
  sanitize_tag_value = { 
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
      runbook_url        = var.runbook_url
      incident_contact   = var.incident_contact
    } : k => v != null ? trimspace(substr(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(v, ",", "-"),
                    ";", "-"
                  ),
                  "&", "and"
                ),
                "\n", "-"
              ),
              "\t", "-"
            ),
            "  ", " "
          ),
          " ", "-"
        ),
        "--", "-"
      ),
      0,
      local.tag_value_max_length
    )) : ""
  }

  # Standard organizational metadata
  organization_tags = {
    Organization    = local.sanitize_tag_value["organization_name"]
    Project         = local.sanitize_tag_value["project_name"]
    Portfolio       = local.sanitize_tag_value["portfolio_name"]
    BusinessUnit    = local.sanitize_tag_value["business_unit"]
    CostCenter      = local.sanitize_tag_value["cost_center"]
    Owner           = local.sanitize_tag_value["owner"]
    ContactEmail    = local.sanitize_tag_value["contact_email"]
  }

  # Infrastructure metadata (account_id omitted to avoid circular dependencies)
  infrastructure_tags = {
    ManagedBy           = "Terraform"
    TerraformModule     = var.terraform_module
    TerraformVersion    = var.terraform_version
    TerraformWorkspace  = terraform.workspace
    ProvisionedBy       = var.provisioned_by
    DeploymentPipeline  = var.deployment_pipeline
    GitCommit           = var.git_commit
    Region              = var.region
    AccountAlias        = var.account_alias
  }

  # Environment and deployment metadata
  # NOTE: Timestamps removed to prevent state churn
  environment_tags = {
    Environment         = var.environment
    EnvironmentType     = var.environment_type
    Layer               = var.layer_name
    LayerPurpose        = local.sanitize_tag_value["layer_purpose"]
    DeploymentPhase     = local.sanitize_tag_value["deployment_phase"]
    DeploymentMethod    = local.sanitize_tag_value["deployment_method"]
    DeploymentDate      = var.deployment_date  # Must be provided externally, no timestamp()
    Version             = var.infrastructure_version
  }

  # Operational metadata (Enhanced for industrial standards)
  operational_tags = {
    CriticalInfra       = var.critical_infrastructure
    BackupRequired      = var.backup_required
    SecurityLevel       = var.security_level
    ComplianceLevel     = var.compliance_level
    DataClassification  = var.data_classification
    DataResidency       = var.data_residency
    EncryptionRequired  = var.encryption_required
    MaintenanceWindow   = var.maintenance_window
    SLA                 = var.sla_tier
    MonitoringLevel     = var.monitoring_level
    DRTier              = var.dr_tier
    RPO                 = var.rpo
    RTO                 = var.rto
    PatchGroup          = var.patch_group
    RunbookUrl          = local.sanitize_tag_value["runbook_url"]
    IncidentContact     = local.sanitize_tag_value["incident_contact"]
  }

  # Cost management tags (FinOps Foundation aligned)
  cost_tags = {
    BillingGroup        = local.sanitize_tag_value["owner"]
    ChargebackCode      = local.sanitize_tag_value["chargeback_code"]
    Budget              = var.budget_name
    CostOptimization    = var.cost_optimization_enabled
    AutoScalingEnabled  = var.auto_scaling_enabled
    InstanceSchedule    = var.instance_schedule
    ResourceType        = var.resource_type
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
  # NOTE: Note Timestamps to prevent Terraform state churn
  # Timestamps should be managed via CI/CD pipeline or external systems
  governance_tags = {
    CreatedBy           = var.created_by
    CreationDate        = var.creation_date  # Must be provided externally
    ChangeTicket        = var.change_ticket
    ComplianceFramework = local.sanitize_tag_value["compliance_framework"]
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

  # Layer-specific tag definitions (extensible via variables)
  # Merged with var.layer_specific_tags for custom additions
  default_layer_tags = var.layer_name == "foundation" ? {
    NetworkTier       = "Foundation"
    VPCPurpose        = "Client-Dedicated"
    NATConfiguration  = "HighAvailability"
  } : var.layer_name == "platform" ? {
    ClusterRole       = "Primary"
    KubernetesVersion = var.kubernetes_version
    NodeGroupType     = "Mixed"
  } : var.layer_name == "observability" ? {
    ObservabilityStack = "FluentBit-Tempo-Prometheus"
    LoggingEnabled     = "true"
    TracingEnabled     = "true"
    MetricsEnabled     = "true"
  } : var.layer_name == "database" || var.layer_name == "database-layer" ? {
    DatabaseEngine     = var.database_engine
    BackupStrategy     = var.backup_strategy
    EncryptionEnabled  = "true"
  } : {}

  # Create layer-specific tag variations
  layer_specific_tags = merge(
    local.filtered_tags,
    local.default_layer_tags,
    var.layer_specific_tags  # Allow custom layer tags
  )

  # Tag count validation (AWS limit is 50, safe limit is 45)
  tag_count = length(local.layer_specific_tags)
  tag_limit_exceeded = local.tag_count > local.safe_tag_limit
  
  # Tag validation results
  tag_validation = {
    total_tags         = local.tag_count
    aws_limit          = local.aws_tag_limit
    safe_limit         = local.safe_tag_limit
    exceeds_safe_limit = local.tag_limit_exceeded
    buffer_remaining   = local.safe_tag_limit - local.tag_count
    status             = local.tag_limit_exceeded ? "WARNING: Tag count exceeds safe limit" : "OK"
  }
}


