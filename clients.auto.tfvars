# ============================================================================
# CENTRALIZED CLIENT CONFIGURATION - SINGLE SOURCE OF TRUTH
# ============================================================================
# Usage: Referenced by all layers via -var-file="../../../../../clients.auto.tfvars"
# Architecture: Client-centric with complete isolation per client
# CIDR Registry: All VPC CIDRs tracked in /cidr-registry.yaml for validation
# ============================================================================

clients = {
  zam = {
    enabled     = true
    client_code = "CLNT-ZAM"
    tier        = "premium"
    
    # ========================================================================
    # NETWORK CONFIGURATION (Layer 01: Foundation)
    # ========================================================================
    # VPC CIDR must be globally unique across ALL regions
    # Validated by: ./scripts/validate-cidr.sh
    network = {
      vpc_cidr = "10.0.0.0/16"  # From cidr-registry.yaml
    }
    
    # ========================================================================
    # SECURITY CONFIGURATION (Layer 01: Foundation)
    # ========================================================================
    security = {
      custom_ports   = [8080, 9000, 3000, 5000]  # Application ports
      database_ports = [5432, 5433, 5434, 5435]  # PostgreSQL ports
    }
    
    # ========================================================================
    # VPN CONFIGURATION (Layer 01: Foundation) - Optional
    # ========================================================================
    # Only configure if client requires Site-to-Site VPN
    vpn = {
      enabled             = true
      customer_gateway_ip = "203.0.113.10"       # Client's firewall public IP
      bgp_asn             = 65001                # Client's BGP ASN
      amazon_side_asn     = 64512                # AWS side BGP ASN
      local_network_cidr  = "10.0.0.0/16"        # Client's on-premises network
      tunnel1_inside_cidr = "169.254.10.0/30"    # VPN tunnel 1 inside CIDR
      tunnel2_inside_cidr = "169.254.10.4/30"    # VPN tunnel 2 inside CIDR
      static_routes_only  = false                 # false = BGP, true = static routes
      description         = "VPN to Client A HQ"
    }
    
    # ========================================================================
    # EKS CONFIGURATION (Layer 02: Platform)
    # ========================================================================
    eks = {
      enabled        = true
      instance_types = ["m5.large", "m5a.large", "t3.xlarge"]
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      disk_size      = 20
      capacity_type  = "SPOT"  # ON-DEMAND or "SPOT"
    }
    
    # ========================================================================
    # ALB CONFIGURATION (Layer 02: Platform)
    # ========================================================================
    alb = {
      enabled                      = true
      type                         = "internet-facing"  # Options: "internet-facing", "internal", "both"
      https_external_port          = 30443  # Custom HTTPS port
      http_external_port           = 30080  # Custom HTTP port
      https_nodeport               = 30443  # EKS NodePort for HTTPS
      http_nodeport                = 30080  # EKS NodePort for HTTP
      redirect_http_to_https       = true   # Redirect HTTP → HTTPS
      enable_deletion_protection   = true   # Production safety
      enable_access_logs           = true   # Log to S3
      enable_waf                   = true   # Enable WAF for public ALB
      enable_sticky_sessions       = false  # Session affinity
      ssl_policy                   = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      ssl_certificate_arn          = "arn:aws:acm:us-east-2:123456789012:certificate/client-a-cert"  # ACM certificate
      ssl_certificate_arn_internal = null   # Optional separate cert for internal ALB
      allowed_cidr_blocks_public   = ["0.0.0.0/0"]  # Internet access
      allowed_cidr_blocks_internal = ["10.0.0.0/16"]  # VPN/Corporate network
      health_check_path            = "/healthz/ready"  # Istio health check
    }
    
    # ========================================================================
    # DNS CONFIGURATION (Layer 02: Platform) - Smart Auto-Discovery
    # ========================================================================
    # Layer 02 automatically discovers zones created by Layer 05
    # NO ZONE IDs NEEDED! Just specify your domain name
    dns = {
      enabled                  = true
      domain_name              = "zam.xyz"             # Layer 05 creates this zone
      public_subdomain         = "app"                      # → app.client-a.xyz
      internal_subdomain       = "internal"                 # → internal.client-a.xyz
      create_route53_records   = true                       # Auto-create DNS records
      create_wildcard_record   = false                      # Optional: *.client-a.xyz
      evaluate_target_health   = true                       # Enable ALB health checks
      # Optional: Specify a separate private zone if you created one manually
      # private_zone_domain_name = "client-a.internal"
    }
    
    # ========================================================================
    # DATABASE CONFIGURATION (Layer 03: Database)
    # ========================================================================
    database = {
      enabled           = true
      instance_type     = "t3.large"
      data_volume_size  = 100  # GB
      wal_volume_size   = 50   # GB
      backup_volume_size = 100 # GB
      enable_replica    = true
    }
    
    # ========================================================================
    # COMPUTE CONFIGURATION (Layer 04: Standalone Compute)
    # ========================================================================
    compute = {
      enabled       = true
      instance_type = "t3.medium"
      instance_count = 2
    }
    
    # ========================================================================
    # CLIENT METADATA - Used Across ALL Layers
    # ========================================================================
    # This metadata is used for tagging, compliance, and cost tracking
    metadata = {
      full_name     = "Client A Corporation"
      industry      = "financial-services"
      contact_email = "ops@client-a.example.com"
      compliance    = ["SOC2", "PCI-DSS", "GDPR"]
      cost_center   = "CC-001"
      business_unit = "Product-Engineering"
    }
  }

  # client-b = {
  #   enabled     = true
  #   client_code = "CLNT-B"
  #   tier        = "standard"
    
  #   # Network
  #   network = {
  #     vpc_cidr = "172.16.0.0/16"
  #   }
    
  #   # Security
  #   security = {
  #     custom_ports   = [8080, 9000, 3000, 5000]
  #     database_ports = [5432, 5433, 5434, 5435]
  #   }
    
  #   # VPN - Disabled for this client
  #   vpn = {
  #     enabled             = false
  #     customer_gateway_ip = ""
  #     bgp_asn             = 0
  #     amazon_side_asn     = 0
  #     local_network_cidr  = ""
  #     tunnel1_inside_cidr = ""
  #     tunnel2_inside_cidr = ""
  #     static_routes_only  = false
  #     description         = ""
  #   }
    
  #   # EKS
  #   eks = {
  #     enabled        = true
  #     instance_types = ["t3.large", "t3.xlarge"]
  #     min_size       = 1
  #     max_size       = 3
  #     desired_size   = 1
  #     disk_size      = 20
  #     capacity_type  = "SPOT"  # Cost savings for standard tier
  #   }
    
  #   # ALB Configuration - Internal only for standard tier
  #   alb = {
  #     enabled                      = true
  #     type                         = "internal"  # Internal ALB only (no public access)
  #     https_external_port          = 30443
  #     http_external_port           = 30080
  #     https_nodeport               = 30443
  #     http_nodeport                = 30080
  #     redirect_http_to_https       = true
  #     enable_deletion_protection   = false  # Standard tier = lower protection
  #     enable_access_logs           = true
  #     enable_waf                   = false  # No WAF for internal ALB
  #     enable_sticky_sessions       = false
  #     ssl_policy                   = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  #     ssl_certificate_arn          = "arn:aws:acm:us-east-2:123456789012:certificate/client-b-cert"
  #     ssl_certificate_arn_internal = null
  #     allowed_cidr_blocks_public   = []  # No public access
  #     allowed_cidr_blocks_internal = ["10.0.0.0/16", "172.16.0.0/12"]  # VPN networks
  #     health_check_path            = "/healthz/ready"
  #   }
    
  #   # DNS Configuration - Smart Auto-Discovery (Internal ALB only)
  #   dns = {
  #     enabled                  = true
  #     domain_name              = "client-b.xyz"             # Layer 05 creates this zone
  #     public_subdomain         = "app"                      # Not used (internal only)
  #     internal_subdomain       = "vpn"                      # → vpn.client-b.xyz
  #     create_route53_records   = true                       # Auto-create DNS records
  #     evaluate_target_health   = true                       # Enable ALB health checks
  #   }
    
  #   # Database
  #   database = {
  #     enabled           = true
  #     instance_type     = "t3.medium"
  #     data_volume_size  = 50
  #     wal_volume_size   = 25
  #     backup_volume_size = 50
  #     enable_replica    = false  # Single instance for standard tier
  #   }
    
  #   # Compute
  #   compute = {
  #     enabled       = false  # Not needed for this client
  #     instance_type = ""
  #     instance_count = 0
  #   }
    
  #   # Metadata
  #   metadata = {
  #     full_name     = "Client B Corporation"
  #     industry      = "technology"
  #     contact_email = "ops@client-b.example.com"
  #     compliance    = ["SOC2"]
  #     cost_center   = "CC-002"
  #     business_unit = "Innovation-Lab"
  #   }
  # }
}

# ============================================================================
# INSTRUCTIONS FOR ADDING NEW CLIENTS
# ============================================================================
# 1. Allocate unique VPC CIDR in /cidr-registry.yaml
# 2. Run: ./scripts/validate-cidr.sh
# 3. Copy template above and customize values
# 4. Set enabled = true when ready to deploy
# 5. Deploy layers 00-06 sequentially
#
# IMPORTANT: 
# - VPC CIDRs must be globally unique
# - Client names must be DNS-compatible (lowercase, hyphens only)
# - Metadata is used for tagging and cost allocation
# ============================================================================
