# ============================================================================
# Layer 02: Platform - Client EKS Configuration
# ============================================================================
# Purpose: EKS node groups for client workloads
# Dependencies: Layer 01 (Foundation) - subnets must exist
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # EKS node group configuration
    eks = {
      enabled         = true
      instance_types  = ["m5.large", "m5a.large", "t3.xlarge"]
      min_size        = 1
      max_size        = 5
      desired_size    = 2
      disk_size       = 20
      capacity_type   = "ON_DEMAND"
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
    
    eks = {
      enabled         = true
      instance_types  = ["t3.large", "t3.xlarge"]
      min_size        = 1
      max_size        = 3
      desired_size    = 1
      disk_size       = 20
      capacity_type   = "SPOT"
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
