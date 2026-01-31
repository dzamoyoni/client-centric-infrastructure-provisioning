# Getting Started Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

This guide walks you through setting up your first client in the infrastructure from scratch. Follow these steps in order for a successful deployment.

**Estimated Time**: 2-3 hours for complete setup  
**Skill Level**: Intermediate Terraform + AWS knowledge required

---

## Prerequisites

### Required Tools

Install and verify these tools before starting:

```bash
# Terraform (>= 1.5.0)
terraform version

# AWS CLI (>= 2.x)
aws --version

# kubectl (for EKS management)
kubectl version --client

# Optional: jq for JSON parsing
jq --version
```

### AWS Credentials

Configure your AWS access:

```bash
# Option 1: AWS Configure
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-2), Output (json)

# Option 2: Environment Variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-2"

# Verify credentials
aws sts get-caller-identity
```

### Required AWS Permissions

Your IAM user/role needs these permissions:
- **VPC**: Full access (VPC, Subnets, Route Tables, IGW, NAT Gateway)
- **Transit Gateway**: Create, attach, manage routes
- **EKS**: Cluster and node group management
- **EC2**: Instances, Security Groups, EBS volumes
- **S3**: Bucket management with KMS
- **KMS**: Key creation and management
- **Route53**: Hosted zone and record management
- **CloudWatch**: Logs and metrics
- **IAM**: Role and policy creation

**Tip**: Use the `AdministratorAccess` policy for initial setup, then restrict later.

---

## Step-by-Step Onboarding

### Step 1: Define Your Client

Edit the client configuration file:

```bash
vim providers/aws/regions/us-east-2/layers/01-foundation/production/clients.auto.tfvars
```

Add your client definition:

```hcl
clients = {
  "acme-corp" = {
    enabled     = true
    client_code = "ACME"
    tier        = "standard"  # or "premium"
    
    network = {
      vpc_cidr    = "10.100.0.0/16"  # Must be unique!
      cidr_offset = 100              # Used for subnet calculations
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
      enabled = false  # Set true if client needs VPN
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

**⚠️ Critical**: Each client MUST have a unique `vpc_cidr`. No overlaps allowed!

### Step 2: Validate CIDR Allocation

Update the CIDR registry:

```bash
vim cidr-registry.yaml
```

Add your client:

```yaml
clients:
  acme-corp:
    vpc_cidr: "10.100.0.0/16"
    region: "us-east-2"
    environment: "production"
    allocated_date: "2026-01-31"
    notes: "ACME Corp onboarding"
```

Run validation:

```bash
./scripts/validate-cidr.sh
```

**Expected output**:
```
[SUCCESS] No duplicate CIDRs found
[SUCCESS] All CIDRs have valid format
[SUCCESS] CIDR Registry Validation: PASSED
```

---

## Layer Deployment

Deploy infrastructure in this exact order. Each layer depends on the previous one.

### Layer 00: Bootstrap (ONE-TIME ONLY)

**Purpose**: Creates S3 backend and observability buckets.

**Important**: This layer only needs to be deployed once per region/environment. Skip if already done.

```bash
cd providers/aws/regions/us-east-2/layers/00-bootstrap/production

# Initialize with local backend
terraform init

# Review what will be created
terraform plan

# Deploy
terraform apply

# Save backend configuration
terraform output backend_config > ../backend-config.json
```

**What gets created**:
- S3 bucket: `terraform-state-us-east-2-production` (with versioning + KMS)
- DynamoDB table: `terraform-state-lock`
- KMS key: `alias/terraform-state-production`
- Per-client S3 buckets: `{client}-logs-{region}-{env}`, `{client}-metrics-{region}-{env}`, `{client}-traces-{region}-{env}`

**State Management**: This layer uses **local backend** (stored in `terraform.tfstate`). ⚠️ **Backup this file!**

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-00-bootstrap)

---

### Layer 01: Foundation (Networking)

**Purpose**: Creates Egress VPC and client VPCs (NAT-less).

```bash
cd providers/aws/regions/us-east-2/layers/01-foundation/production

# Initialize with S3 backend
terraform init -backend-config=backend.hcl

# Review changes
terraform plan

# Deploy
terraform apply
```

**What gets created for your client**:
- VPC with custom CIDR
- Public subnets (2 AZs) with Internet Gateway
- Private subnets (2 AZs) - **NO NAT Gateways**
- EKS subnets (/20 blocks for pods)
- Database and compute subnets
- Security groups
- VPC Flow Logs

**Time**: ~5-10 minutes

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-01-foundation)

---

### Layer 01.5: Transit Gateway (Centralized Routing)

**Purpose**: Connects all VPCs for centralized internet egress.

```bash
cd providers/aws/regions/us-east-2/layers/01.5-transit-gateway/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**What gets created**:
- Transit Gateway
- VPC attachments (Egress VPC + all client VPCs)
- Route tables and associations
- Default route `0.0.0.0/0` → Transit Gateway → Egress VPC

**Time**: ~10-15 minutes

**Verify routing**:
```bash
# Check client VPC routes
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<client-vpc-id>"
```

📘 **Deep Dive**: [Networking Guide](NETWORKING.md#transit-gateway-architecture)

---

### Layer 02: Platform (EKS Clusters)

**Purpose**: Creates dedicated EKS cluster for your client.

```bash
cd providers/aws/regions/us-east-2/layers/02-platform/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Configure kubectl access
aws eks update-kubeconfig \
  --region us-east-2 \
  --name acme-corp-production-us-east-2 \
  --alias acme-corp

# Verify cluster
kubectl get nodes
```

**Time**: ~15-20 minutes

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-02-platform)

---

### Layer 03: Database (PostgreSQL)

**Purpose**: Deploys PostgreSQL master + replica.

**⚠️ Security**: Create secrets file (never commit to Git!):

```bash
cd providers/aws/regions/us-east-2/layers/03-database/production

cat > database-secrets.tfvars << 'EOF'
database_passwords = {
  "acme-corp" = "SecurePassword123!"
}

replication_passwords = {
  "acme-corp" = "ReplicaPassword456!"
}
EOF

# Set restrictive permissions
chmod 600 database-secrets.tfvars

# Deploy
terraform init -backend-config=backend.hcl
terraform plan -var-file=database-secrets.tfvars
terraform apply -var-file=database-secrets.tfvars
```

**Time**: ~10-15 minutes

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-03-database)

---

### Layer 04: Standalone Compute (Optional)

**Purpose**: Analytics and batch processing instances.

```bash
cd providers/aws/regions/us-east-2/layers/04-standalone-compute/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Skip if**: Client doesn't need standalone compute (only using Kubernetes).

**Time**: ~5 minutes

---

### Layer 05: Cluster Services (Kubernetes Controllers)

**Purpose**: Installs essential services in EKS cluster.

```bash
cd providers/aws/regions/us-east-2/layers/05-cluster-services/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Verify services
kubectl --context acme-corp get pods -n kube-system
kubectl --context acme-corp get pods -n istio-system
```

**Services installed**:
- Cluster Autoscaler
- AWS Load Balancer Controller
- Metrics Server
- ExternalDNS
- Istio Service Mesh

**Time**: ~10-15 minutes

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-05-cluster-services)

---

### Layer 06: Observability (Monitoring Stack)

**Purpose**: Deploys Prometheus, Grafana, Loki, Tempo.

```bash
cd providers/aws/regions/us-east-2/layers/06-observability/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Access Grafana (port-forward)
kubectl --context acme-corp port-forward -n observability svc/grafana 3000:80
```

Open browser: `http://localhost:3000`  
Default credentials: `admin` / (check terraform.tfvars)

**Time**: ~10-15 minutes

📘 **Deep Dive**: [Layer Deployment Guide](LAYER-DEPLOYMENT.md#layer-06-observability)

---

## Post-Deployment Verification

### 1. Verify Network Connectivity

Test internet access from EKS cluster:

```bash
# Deploy test pod
kubectl --context acme-corp run test-pod --image=nicolaka/netshoot -it --rm -- bash

# Inside pod:
curl -I https://www.google.com  # Should succeed via TGW → Egress VPC → NAT
```

### 2. Verify DNS Setup

Check Route53 zone delegation:

```bash
# Get zone ID
aws route53 list-hosted-zones | grep acme-corp

# Test DNS resolution
dig NS acme-corp.xyz.com
```

### 3. Verify Monitoring

- Access Grafana dashboard
- Check Prometheus targets: `http://localhost:3000/monitoring/prometheus/targets`
- Verify logs in Loki
- Check distributed traces in Tempo

### 4. Verify Cost Tagging

```bash
# Check resource tags
aws ec2 describe-vpcs --vpc-ids <vpc-id> | jq '.Vpcs[].Tags'

# Should include:
# - Client: acme-corp
# - Environment: production
# - ManagedBy: Terraform
# - CostCenter: CC-ACME-001
```

---

## Common First-Time Issues

### Issue: Terraform state lock error

**Solution**:
```bash
# Check lock status
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (if no one else is running Terraform)
terraform force-unlock <lock-id>
```

### Issue: EKS cluster unreachable

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-2 --name <cluster-name>

# Check your IP is in management_cidr_blocks
vim providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfvars
```

### Issue: NAT Gateway costs high

**Expected**: Single pair of NAT Gateways in Egress VPC costs ~$65/month (cost-shared across all clients).

---

## Next Steps

1. **Deploy Application**: Create Kubernetes Deployment + Service
2. **Set Up DNS**: Use ExternalDNS annotations
3. **Configure Monitoring**: Add custom Grafana dashboards
4. **Review Security**: [Security Guide](SECURITY.md)
5. **Optimize Costs**: [Cost Optimization Guide](COST-OPTIMIZATION.md)

---

## Getting Help

- **Documentation**: [Full deployment guide](LAYER-DEPLOYMENT.md)
- **Troubleshooting**: [Common issues](TROUBLESHOOTING.md)
- **Slack**: #platform-engineering
- **Email**: platform-team@company.com

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
