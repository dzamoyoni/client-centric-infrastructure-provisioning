# ============================================================================
# Layer 06: Observability - Client Metadata Only
# ============================================================================
# Purpose: Prometheus, Grafana, Loki, Tempo (shared with client prefixes)
# Dependencies: Layer 02 (Platform) - EKS cluster must exist
# Note: Observability stack is shared, data isolated via client prefixes
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # Client metadata for tagging and data segmentation
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
