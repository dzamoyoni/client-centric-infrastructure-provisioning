# ============================================================================
# Layer 00: Bootstrap - Client Configuration
# ============================================================================
# Purpose: Define clients for observability bucket provisioning
# Note: Only metadata is required (no network/eks/storage config for bootstrap)
# 
# This file should mirror the enabled clients from other layers
# When you add a client to foundation/platform/database layers, add them here
# ============================================================================

clients = {
  client-a = {
    enabled     = true
    client_code = "CLNT-A"
    tier        = "premium"
    
    # Client metadata (REQUIRED for tagging)
    metadata = {
      full_name       = "Client A"
      industry        = "Testing Services"
      contact_email   = "dennisjuma00@gmail.com"
      compliance      = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center     = "CLNT-A-001"
      business_unit   = "Product-Engineering"
    }
    
  }
  client-b = {
    enabled     = true
    client_code = "CLNT-B"
    tier        = "premium"
    
    # Client metadata (REQUIRED for tagging)
    metadata = {
      full_name       = "Client B"
      industry        = "Testing Services"
      contact_email   = "dennisjuma00@gmail.com"
      compliance      = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center     = "CLNT-B-001"
      business_unit   = "Product-Engineering"
    }
    
  }
  # client-b = {
  #   enabled     = true
  #   client_code = "CLNT-B"
  #   tier        = "premium"
    
  #   # Client metadata (REQUIRED for tagging)
  #   metadata = {
  #     full_name       = "Client B"
  #     industry        = "Testing Services"
  #     contact_email   = "dennisjuma00@gmail.com"
  #     compliance      = ["SOC2", "PCI-DSS", "GDPR"]
  #     cost_center     = "CLNT-A-001"
  #     business_unit   = "Product-Engineering"
  #   }
    
  # }
  

  # Add additional clients here as they are onboarded
  # Each client will automatically get:
  #   - {client-name}-logs-{region}-{environment}
  #   - {client-name}-metrics-{region}-{environment}
  #   - {client-name}-traces-{region}-{environment}
  
  # Example:
  # est-test-b = {
  #   enabled     = true
  #   client_code = "ETB"
  #   tier        = "standard"
  #   
  #   metadata = {
  #     full_name       = "EST Test Client B"
  #     industry        = "technology"
  #     contact_email   = "ops@client-b.example.com"
  #     compliance      = ["SOC2"]
  #     cost_center     = "CC-002"
  #     business_unit   = "Innovation-Lab"
  #   }
  # }
}
