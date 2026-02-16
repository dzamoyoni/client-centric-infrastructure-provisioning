# ============================================================================
# Shared Configuration Module - Outputs
# ============================================================================

# Output the complete layer configuration
output "layer_config" {
  description = "Complete configuration for the requested layer"
  value       = local.layer_config
}

# Individual outputs for convenience
output "layer_name" {
  description = "Layer name"
  value       = local.layer_config.name
}

output "layer_purpose" {
  description = "Layer purpose description"
  value       = local.layer_config.purpose
}

output "deployment_phase" {
  description = "Deployment phase"
  value       = local.layer_config.deployment_phase
}

output "security_level" {
  description = "Security level"
  value       = local.layer_config.security_level
}

output "sla_tier" {
  description = "SLA tier"
  value       = local.layer_config.sla_tier
}

output "monitoring_level" {
  description = "Monitoring level"
  value       = local.layer_config.monitoring_level
}

output "maintenance_window" {
  description = "Maintenance window"
  value       = local.layer_config.maintenance_window
}

output "dr_tier" {
  description = "Disaster recovery tier"
  value       = local.layer_config.dr_tier
}

output "rpo" {
  description = "Recovery point objective"
  value       = local.layer_config.rpo
}

output "rto" {
  description = "Recovery time objective"
  value       = local.layer_config.rto
}

output "patch_group" {
  description = "Patch group"
  value       = local.layer_config.patch_group
}

output "resource_type" {
  description = "Resource type"
  value       = local.layer_config.resource_type
}

output "chargeback_code" {
  description = "Chargeback code"
  value       = local.layer_config.chargeback_code
}

output "runbook_url" {
  description = "Runbook URL"
  value       = local.layer_config.runbook_url
}

output "incident_contact" {
  description = "Incident contact"
  value       = local.layer_config.incident_contact
}
