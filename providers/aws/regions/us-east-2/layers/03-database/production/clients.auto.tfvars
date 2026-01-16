# ============================================================================
# Layer 03: Database - Client Storage Configuration
# ============================================================================
# Purpose: PostgreSQL database backup retention settings
# Dependencies: Layer 01 (Foundation) - database subnets must exist
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # Database storage configuration
    storage = {
      backup_retention_days = 90  # Premium tier gets longer retention
    }
    
    # Client metadata
    metadata = {
      full_name       = "EST Test Client A"
      industry        = "financial-services"
      contact_email   = "ops@client-a.example.com"
      compliance      = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center     = "CC-001"
      business_unit   = "Product-Engineering"
    }
  }

  est-test-b = {
    enabled     = true
    client_code = "ETB"
    tier        = "standard"
    
    storage = {
      backup_retention_days = 30  # Standard tier
    }
    
    metadata = {
      full_name       = "EST Test Client B"
      industry        = "technology"
      contact_email   = "ops@client-b.example.com"
      compliance      = ["SOC2"]
      cost_center     = "CC-002"
      business_unit   = "Innovation-Lab"
    }
  }
}