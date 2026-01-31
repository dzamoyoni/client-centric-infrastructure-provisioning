# Client Configuration Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

This guide explains how to configure client definitions in `clients.auto.tfvars` files.

---

## Main Configuration Files

### 1. clients.auto.tfvars (All Layers)

**Single source of truth** for client definitions. Copy this file to all layer directories.

**Location**: `providers/aws/regions/us-east-2/layers/*/production/clients.auto.tfvars`

**Complete Example**:
```hcl
clients = {
  "acme-corp" = {
    enabled     = true
    client_code = "ACME"
    tier        = "standard"  # or "premium"
    
    network = {
      vpc_cidr    = "10.100.0.0/16"  # Must be unique!
      cidr_offset = 100              # For subnet calculations
    }
    
    eks = {
      enabled        = true
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 5
      desired_size   = 2
      disk_size      = 50
      capacity_type  = "ON_DEMAND"  # or "SPOT"
    }
    
    compute = {
      analytics_enabled = true
      instance_type     = "t3.large"
      root_volume_size  = 30
      data_volume_size  = 100
    }
    
    storage = {
      enable_dedicated_buckets = true
      backup_retention_days    = 30
    }
    
    security = {
      database_ports = [5432, 5433]
      custom_ports   = [8080, 9090]
    }
    
    vpn = {
      enabled              = false
      customer_gateway_ip  = ""
      bgp_asn             = 65001
      amazon_side_asn     = 64512
      static_routes_only  = true
      local_network_cidr  = ""
      tunnel1_inside_cidr = ""
      tunnel2_inside_cidr = ""
      description         = ""
    }
    
    metadata = {
      full_name     = "ACME Corporation"
      industry      = "Technology"
      contact_email = "ops@acme.com"
      compliance    = ["SOC2", "HIPAA"]
      cost_center   = "CC-ACME-001"
      business_unit = "Enterprise"
    }
  }
}
```

---

## Field Descriptions

### Core Fields
- `enabled`: Master switch (true/false)
- `client_code`: Short identifier (used in tags)
- `tier`: "standard" or "premium" (affects resource allocation)

### Network Configuration
- `vpc_cidr`: Must be unique across all clients
- `cidr_offset`: Used for subnet calculations (match 3rd octet)

### EKS Configuration
- `instance_types`: EC2 instance types for nodes
- `min_size`/`max_size`: Autoscaling limits
- `desired_size`: Initial node count
- `capacity_type`: "ON_DEMAND" or "SPOT"

### VPN Configuration (Optional)
- `enabled`: Set to true for Site-to-Site VPN
- `customer_gateway_ip`: On-premises gateway IP
- `local_network_cidr`: On-premises network CIDR

---

## terraform.tfvars (Per Layer)

Layer-specific configuration shared across all clients.

**Layer 02 (Platform) Example**:
```hcl
environment              = "production"
region                   = "us-east-2"
cluster_version          = "1.31"
enable_public_access     = true
management_cidr_blocks   = ["203.0.113.0/24"]
terraform_state_bucket   = "terraform-state-us-east-2-production"
terraform_state_region   = "us-east-2"
```

---

## CIDR Registry

Track allocated CIDRs in `cidr-registry.yaml`:

```yaml
clients:
  acme-corp:
    vpc_cidr: "10.100.0.0/16"
    region: "us-east-2"
    environment: "production"
    allocated_date: "2026-01-31"
    notes: "ACME Corp production"
```

**Always validate**:
```bash
./scripts/validate-cidr.sh
```

---

## Best Practices

1. **Use symlinks** to avoid file drift:
   ```bash
   # Create master file
   vim providers/aws/regions/us-east-2/layers/clients.auto.tfvars
   
   # Link to all layers
   for layer in 01-foundation 01.5-transit-gateway 02-platform 03-database 04-standalone-compute 05-cluster-services 06-observability; do
     ln -s ../../clients.auto.tfvars providers/aws/regions/us-east-2/layers/${layer}/production/clients.auto.tfvars
   done
   ```

2. **Version control all changes**
3. **Validate CIDR before adding clients**
4. **Use consistent naming** (lowercase, hyphens)

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Client onboarding
- [Architecture](ARCHITECTURE.md) - CIDR strategy
- [Troubleshooting](TROUBLESHOOTING.md) - Configuration issues

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
