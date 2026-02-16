# Deployment Order - Complete Guide

## Critical Dependency: DNS Zones

**IMPORTANT:** Layer 05 creates Route53 zones → Layer 02 discovers them for ALB DNS

## Correct Deployment Sequence

### Initial Deployment (New Client)

```bash
# Step 1: Bootstrap (S3, DynamoDB for state)
cd providers/aws/regions/us-east-2/layers/00-bootstrap/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Step 2: Foundation (VPC, Subnets, Security Groups)
cd ../../../01-foundation/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Step 3: Transit Gateway (Hub-and-Spoke)
cd ../../../01.5-transit-gateway/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Step 4: Platform (EKS, ALB - NO DNS YET)
cd ../../../02-platform/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"
# Output: "Waiting for Route53 zone (deploy Layer 05)"

# Step 5: Database (RDS PostgreSQL)
cd ../../../03-database/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Step 6: Standalone Compute (EC2 instances)
cd ../../../04-standalone-compute/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Step 7: Cluster Services (Route53 Zones, ExternalDNS, Istio)
cd ../../../05-cluster-services/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"
# ✅ Creates Route53 zones: client-a.xyz, client-b.xyz

# Step 8: Re-run Platform to Create ALB DNS
cd ../../../02-platform/production
terraform apply -var-file="../../../../../../clients.auto.tfvars"
# ✅ Discovers zones and creates: app.client-a.xyz → ALB

# Step 9: Observability (Monitoring, Logging)
cd ../../../06-observability/production
terraform init
terraform apply -var-file="../../../../../../clients.auto.tfvars"
```

---

## Why This Order?

### Layer Dependencies

```
00-bootstrap          (No dependencies)
    ↓
01-foundation         (Needs: 00)
    ↓
01.5-transit-gateway  (Needs: 01)
    ↓
02-platform           (Needs: 01, 01.5)
    ↓                 ↓
03-database          05-cluster-services
    ↓                 ↓
04-compute           (Creates Route53 zones)
                      ↓
                   02-platform (re-run)
                      ↓
                   (Discovers zones, creates ALB DNS)
                      ↓
                   06-observability
```

### DNS-Specific Flow

```
1. Layer 02 (First Run)
   - Creates: ALB infrastructure
   - DNS Status: "Waiting for Route53 zone"
   - Output: Use ALB DNS names directly

2. Layer 05
   - Creates: Route53 zones (client-a.xyz)
   - Creates: ExternalDNS controller
   - Output: Zone IDs

3. Layer 02 (Second Run)
   - Discovers: Zones by domain name
   - Creates: app.client-a.xyz → ALB
   - Output: "DNS records active"
```

---

## Alternative: Skip DNS on First Deployment

If you want to skip DNS initially:

### Option A: Disable DNS in clients.auto.tfvars

```hcl
clients = {
  client-a = {
    dns = {
      enabled                = false  # Skip DNS completely
      domain_name            = "client-a.xyz"
      create_route53_records = false
    }
  }
}
```

**Result:** Layer 02 skips all DNS, use ALB DNS names directly

### Option B: Enable DNS After Layer 05

```hcl
# Initial deployment
clients = {
  client-a = {
    dns = {
      enabled                = true
      domain_name            = "client-a.xyz"
      create_route53_records = false  # Don't create records yet
    }
  }
}

# After Layer 05 deployment
clients = {
  client-a = {
    dns = {
      enabled                = true
      domain_name            = "client-a.xyz"
      create_route53_records = true   # ✅ Now create records
    }
  }
}
```

---

## Verification Commands

### After Layer 02 (First Run)
```bash
# Check ALB exists
terraform output client_endpoints

# Expected output:
# client_endpoints = {
#   client-a = {
#     alb_public_dns = "client-a-public-alb-123.us-east-2.elb.amazonaws.com"
#     dns_status = "Waiting for Route53 zone (deploy Layer 05)"
#   }
# }

# Test ALB directly
curl https://client-a-public-alb-123.us-east-2.elb.amazonaws.com:30443
```

### After Layer 05
```bash
# Check zones created
terraform output client_zone_ids

# Expected output:
# client_zone_ids = {
#   client-a = "Z1234567890ABCDEF"
#   client-b = "Z9876543210FEDCBA"
# }

# Verify zone exists
aws route53 list-hosted-zones | grep client-a.xyz
```

### After Layer 02 (Second Run)
```bash
# Check DNS records created
terraform output dns_zone_discovery_status

# Expected output:
# dns_zone_discovery_status = {
#   client-a = {
#     public_zone_found = true
#     zone_id = "Z1234567890ABCDEF"
#     status_message = "Zone discovered - DNS records created"
#   }
# }

# Verify DNS resolution
dig app.client-a.xyz
nslookup app.client-a.xyz

# Test via DNS
curl https://app.client-a.xyz:30443
```

---

## Common Issues

### Issue 1: "Zone not found" on Layer 02

**Cause:** Layer 05 not deployed yet

**Solution:**
```bash
# Deploy Layer 05 first
cd layers/05-cluster-services/production
terraform apply -var-file="../../../../../../clients.auto.tfvars"

# Then re-run Layer 02
cd layers/02-platform/production
terraform apply -var-file="../../../../../../clients.auto.tfvars"
```

### Issue 2: DNS records not created

**Check configuration:**
```hcl
dns = {
  enabled                = true   # ✅ Must be true
  create_route53_records = true   # ✅ Must be true
  domain_name            = "client-a.xyz"  # ✅ Must match Layer 05 zone
}
```

### Issue 3: Wrong domain name

**Symptom:** Zone discovered but wrong domain

**Fix in `/clients.auto.tfvars`:**
```hcl
# Layer 05 creates: client-a.xyz
# Layer 02 must use same domain

dns = {
  domain_name = "client-a.xyz"  # Must match Layer 05
}
```

---

## Summary

### Correct Order
1. Deploy Layers 00 → 01 → 01.5 → 02 (ALB without DNS)
2. Deploy Layer 05 (Create zones)
3. Re-run Layer 02 (Create ALB DNS)
4. Deploy remaining layers

### Key Points
- ✅ Layer 05 creates Route53 zones
- ✅ Layer 02 discovers zones by domain name
- ✅ No zone IDs needed in configuration
- ✅ Re-run Layer 02 after Layer 05 for DNS
- ✅ Keep ExternalDNS for application DNS
