# ============================================================================
# Layer 01: Foundation - Client Network Configuration
# ============================================================================
# Purpose: Per-client VPC infrastructure (VPC, Subnets, NAT, VPN, Security Groups)
# Architecture: Each client gets a DEDICATED VPC with unique CIDR
# Dependencies: None (base layer)
# CIDR Registry: All VPC CIDRs tracked in /cidr-registry.yaml for global uniqueness
# ============================================================================

clients = {
  est-test-a = {
    enabled     = true
    client_code = "ETA"
    tier        = "premium"
    
    # Per-Client VPC CIDR - MUST be globally unique across ALL regions
    # Validated by: ./scripts/validate-cidr.sh
    network = {
      vpc_cidr = "10.0.0.0/16"  # From cidr-registry.yaml
      # Subnet breakdownwithin their VPC
      subnets = {
        eks      = ["10.0.1.0/20", "10.0.2.0/20"]  # EKS subnets
        database = ["10.0.3.0/20", "10.0.4.0/20"]  # DB subnets
        compute  = ["10.0.5.0/20", "10.0.6.0/20"]  # Compute subnets
      }
    }
    
    # Security group ports
    security = {
      custom_ports   = [8080, 9000, 3000, 5000]
      database_ports = [5432, 5433, 5434, 5435]
    }
    
    # Per-client VPN configuration (ONLY if client needs VPN)
    # To enable VPN, uncomment and provide ALL required values (NO DEFAULTS):
    vpn = {
      enabled             = true
      customer_gateway_ip = "203.0.113.10"      # REQUIRED: Client's firewall public IP
      bgp_asn             = 65001                # REQUIRED: Client's BGP ASN
      amazon_side_asn     = 64512                # REQUIRED: AWS side BGP ASN
      local_network_cidr  = "10.0.0.0/16"       # REQUIRED: Client's on-prem network CIDR
      tunnel1_inside_cidr = "169.254.10.0/30"   # REQUIRED: Tunnel 1 inside CIDR
      tunnel2_inside_cidr = "169.254.10.4/30"   # REQUIRED: Tunnel 2 inside CIDR
      static_routes_only  = false                # REQUIRED: true=static routes, false=BGP
      description         = "VPN to Client A HQ" # REQUIRED: Description for tagging
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
    
    # Per-Client VPC CIDR - MUST be globally unique across ALL regions
    network = {
      vpc_cidr = "172.16.0.0/16"  # From cidr-registry.yaml
    }
    
    security = {
      custom_ports   = [8080, 9000, 3000]
      database_ports = [5432, 5433]
    }
    
    # No VPN for this client - omit vpn block entirely
    # If vpn block is omitted or vpn.enabled = false, no VPN is created
    
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
