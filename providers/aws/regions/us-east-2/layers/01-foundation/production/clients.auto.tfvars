# ============================================================================
# Layer 01: Foundation - Client Network Configuration
# ============================================================================
# Purpose: Per-client VPC infrastructure (VPC, Subnets, NAT, VPN, Security Groups)
# Architecture: Each client gets a DEDICATED VPC with unique CIDR
# Dependencies: None (base layer)
# CIDR Registry: All VPC CIDRs tracked in /cidr-registry.yaml for global uniqueness
# ============================================================================

clients = {
  client-a = {
    enabled     = true
    client_code = "CLNT-A"
    tier        = "premium"
    
    # Per-Client VPC CIDR - MUST be globally unique across ALL regions
    # Validated by: ./scripts/validate-cidr.sh
    network = {
      vpc_cidr = "10.0.0.0/16"  # From cidr-registry.yaml
      # Subnet breakdownwithin their VPC
      subnets = {
        eks      = ["10.0.16.0/20", "10.0.17.0/20"]  # EKS subnets
        database = ["10.0.48.0/20", "10.0.49.0/20"]  # DB subnets
        compute  = ["10.0.64.0/20", "10.0.65.0/20"]  # Compute subnets
      }
    }
    
    # Security group ports
    security = {
      custom_ports   = [8080, 9000, 3000, 5000]
      database_ports = [5432, 5433, 5434, 5435]
    }
    
    # Per-client VPN configuration (ONLY if client needs VPN)
# Disable injection for manual deplo# Disable injection for manual deployment# Disable injection for manual deploymentyment    
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
      full_name       = "Client-A"
      industry        = "financial-services"
      contact_email   = "ops@client-a.example.com"
      compliance      = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center     = "CC-001"
      business_unit   = "Product-Engineering"
    }
  }

  client-b = {
    enabled     = true
    client_code = "CLNT-B"
    tier        = "premium"
    
    # Per-Client VPC CIDR - MUST be globally unique across ALL regions
    # Validated by: ./scripts/validate-cidr.sh
    network = {
      vpc_cidr = "172.16.0.0/16"  # From cidr-registry.yaml
      # Subnet breakdownwithin their VPC
      subnets = {
        eks      = ["172.16.1.0/20", "172.16.2.0/20"]  # EKS subnets
        database = ["172.16.48.0/20", "172.16.49.0/20"]  # DB subnets
        compute  = ["172.16.64.0/20", "172.16.65.0/20"]  # Compute subnets
      }
    }
    
    # Security group ports
    security = {
      custom_ports   = [8080, 9000, 3000, 5000]
      database_ports = [5432, 5433, 5434, 5435]
    }
    
    # Per-client VPN configuration (ONLY if client needs VPN)
# Disable injection for manual deplo# Disable injection for manual deployment# Disable injection for manual deploymentyment    
    vpn = {
      enabled             = true
      customer_gateway_ip = "203.0.114.10"      # REQUIRED: Client's firewall public IP
      bgp_asn             = 65001                # REQUIRED: Client's BGP ASN
      amazon_side_asn     = 64512                # REQUIRED: AWS side BGP ASN
      local_network_cidr  = "192.168.0.0/16"       # REQUIRED: Client's on-prem network CIDR
      tunnel1_inside_cidr = "169.254.6.0/30"   # REQUIRED: Tunnel 1 inside CIDR
      tunnel2_inside_cidr = "169.254.6.4/30"   # REQUIRED: Tunnel 2 inside CIDR
      static_routes_only  = false                # REQUIRED: true=static routes, false=BGP
      description         = "VPN to Client B HQ" # REQUIRED: Description for tagging
    }
    
    # Client metadata
    metadata = {
      full_name       = "Client-B"
      industry        = "financial-services"
      contact_email   = "ops@client-a.example.com"
      compliance      = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center     = "CC-001"
      business_unit   = "Product-Engineering"
    }
  }
}
