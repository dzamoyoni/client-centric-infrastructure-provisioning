# ============================================================================
# Layer 04: Standalone Compute - Client Analytics Configuration
# ============================================================================
# Purpose: EC2 instances for analytics/data processing workloads
# Dependencies: Layer 01 (Foundation) - application subnets must exist
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # Standalone compute configuration
    compute = {
      analytics_enabled = true
      instance_type     = "t3.large"
      root_volume_size  = 30
      data_volume_size  = 50
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
    
    compute = {
      analytics_enabled = true
      instance_type     = "t3.medium"
      root_volume_size  = 20
      data_volume_size  = 30
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
