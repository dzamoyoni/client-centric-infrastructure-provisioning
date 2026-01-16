# ============================================================================
# Layer 05: Shared Services - Client Metadata Only
# ============================================================================
# Purpose: Route53, Istio service mesh (shared across all clients)
# Dependencies: Layer 02 (Platform) - EKS cluster must exist
# Note: Shared services are provisioned once for ALL clients
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # Client metadata for tagging shared resources
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
