# ============================================================================
# Shared Configuration Module
# ============================================================================
# Purpose: Centralized layer metadata to eliminate duplication across layers
# Usage: Each layer imports this module to get its configuration
# ============================================================================

locals {
  # Complete metadata for all infrastructure layers
  all_layer_metadata = {
    "00-bootstrap" = {
      name               = "bootstrap"
      purpose            = "State Backend & KMS Infrastructure"
      deployment_phase   = "Phase-0"
      security_level     = "Critical"
      sla_tier           = "Platinum"
      monitoring_level   = "Premium"
      maintenance_window = "Sunday-00:00-02:00-UTC"
      dr_tier            = "Tier-1"
      rpo                = "1h"
      rto                = "1h"
      patch_group        = "Critical"
      resource_type      = "S3-KMS"
      chargeback_code    = "EST1-BOOTSTRAP-001"
      runbook_url        = "https://wiki.company.com/runbooks/bootstrap"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "01-foundation" = {
      name               = "foundation"
      purpose            = "VPC and Network Infrastructure"
      deployment_phase   = "Phase-1"
      security_level     = "High"
      sla_tier           = "Gold"
      monitoring_level   = "Enhanced"
      maintenance_window = "Sunday-00:00-04:00-UTC"
      dr_tier            = "Tier-2"
      rpo                = "4h"
      rto                = "4h"
      patch_group        = "Critical"
      resource_type      = "VPC"
      chargeback_code    = "EST1-FOUNDATION-001"
      runbook_url        = "https://wiki.company.com/runbooks/network-foundation"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "01.5-transit-gateway" = {
      name               = "transit-gateway"
      purpose            = "Centralized Network Routing Hub"
      deployment_phase   = "Phase-1.5"
      security_level     = "High"
      sla_tier           = "Gold"
      monitoring_level   = "Enhanced"
      maintenance_window = "Sunday-00:00-04:00-UTC"
      dr_tier            = "Tier-2"
      rpo                = "4h"
      rto                = "4h"
      patch_group        = "Critical"
      resource_type      = "TGW"
      chargeback_code    = "EST1-TGW-001"
      runbook_url        = "https://wiki.company.com/runbooks/transit-gateway"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "02-platform" = {
      name               = "platform"
      purpose            = "EKS Cluster Management"
      deployment_phase   = "Phase-2"
      security_level     = "Critical"
      sla_tier           = "Platinum"
      monitoring_level   = "Premium"
      maintenance_window = "Sunday-02:00-04:00-UTC"
      dr_tier            = "Tier-1"
      rpo                = "1h"
      rto                = "1h"
      patch_group        = "Critical"
      resource_type      = "EKS"
      chargeback_code    = "EST1-PLATFORM-001"
      runbook_url        = "https://wiki.company.com/runbooks/eks-platform"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "03-database" = {
      name               = "database"
      purpose            = "PostgreSQL Database Management"
      deployment_phase   = "Phase-3"
      security_level     = "Critical"
      sla_tier           = "Platinum"
      monitoring_level   = "Premium"
      maintenance_window = "Sunday-03:00-05:00-UTC"
      dr_tier            = "Tier-1"
      rpo                = "1h"
      rto                = "1h"
      patch_group        = "Critical"
      resource_type      = "RDS"
      chargeback_code    = "EST1-DATABASE-001"
      runbook_url        = "https://wiki.company.com/runbooks/postgresql-database"
      incident_contact   = "database-oncall@company.com"
    }
    
    "04-standalone-compute" = {
      name               = "standalone-compute"
      purpose            = "Analytics and Batch Processing"
      deployment_phase   = "Phase-4"
      security_level     = "Medium"
      sla_tier           = "Silver"
      monitoring_level   = "Standard"
      maintenance_window = "Sunday-04:00-06:00-UTC"
      dr_tier            = "Tier-3"
      rpo                = "24h"
      rto                = "12h"
      patch_group        = "Standard"
      resource_type      = "EC2"
      chargeback_code    = "EST1-COMPUTE-001"
      runbook_url        = "https://wiki.company.com/runbooks/standalone-compute"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "05-cluster-services" = {
      name               = "cluster-services"
      purpose            = "Kubernetes Controllers and Services"
      deployment_phase   = "Phase-5"
      security_level     = "High"
      sla_tier           = "Gold"
      monitoring_level   = "Enhanced"
      maintenance_window = "Sunday-02:00-04:00-UTC"
      dr_tier            = "Tier-2"
      rpo                = "4h"
      rto                = "4h"
      patch_group        = "Critical"
      resource_type      = "K8S-Controllers"
      chargeback_code    = "EST1-CLUSTER-SVC-001"
      runbook_url        = "https://wiki.company.com/runbooks/cluster-services"
      incident_contact   = "platform-oncall@company.com"
    }
    
    "06-observability" = {
      name               = "observability"
      purpose            = "Monitoring, Logging, and Tracing"
      deployment_phase   = "Phase-6"
      security_level     = "High"
      sla_tier           = "Gold"
      monitoring_level   = "Enhanced"
      maintenance_window = "Sunday-04:00-06:00-UTC"
      dr_tier            = "Tier-2"
      rpo                = "4h"
      rto                = "4h"
      patch_group        = "Critical"
      resource_type      = "Observability"
      chargeback_code    = "EST1-OBSERVABILITY-001"
      runbook_url        = "https://wiki.company.com/runbooks/observability"
      incident_contact   = "platform-oncall@company.com"
    }
  }
  
  # Get configuration for the requested layer
  layer_config = local.all_layer_metadata[var.layer_id]
}
