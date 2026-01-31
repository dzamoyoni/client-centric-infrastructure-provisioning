# Layer Deployment Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

Complete reference for deploying all 7 infrastructure layers (00-06). Deploy in order as each layer depends on the previous one.

---

## Layer 00: Bootstrap

**Purpose**: S3 backend + KMS + observability buckets  
**Deploy Once**: Per region/environment  
**Time**: ~5 minutes

### What Gets Created
- S3: `terraform-state-{region}-{env}` (versioning + KMS)
- DynamoDB: `terraform-state-lock`
- KMS: `alias/terraform-state-{env}`
- Per-client buckets: `{client}-logs/metrics/traces-{region}-{env}`

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/00-bootstrap/production

# Uses local backend
terraform init
terraform plan
terraform apply

# Save backend config
terraform output backend_config > ../backend-config.json
```

### Backend Configuration
```hcl
bucket         = "terraform-state-us-east-2-production"
region         = "us-east-2"
dynamodb_table = "terraform-state-lock"
encrypt        = true
kms_key_id     = "alias/terraform-state-production"
```

📘 [Full Guide](GETTING-STARTED.md#layer-00-bootstrap)

---

## Layer 01: Foundation

**Purpose**: Egress VPC + client VPCs (NAT-less)  
**Time**: ~10 minutes

### What Gets Created
- Egress VPC: 10.255.0.0/16 with NAT Gateways
- Per-client VPC with subnets (no NAT)
- Security groups
- VPC Flow Logs

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/01-foundation/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### Validation
```bash
# Check egress VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=egress-vpc-us-east-2"

# Check client VPCs
aws ec2 describe-vpcs --filters "Name=tag:Client,Values={client-name}"
```

📘 [Full Guide](GETTING-STARTED.md#layer-01-foundation)

---

## Layer 01.5: Transit Gateway

**Purpose**: Centralized routing hub  
**Time**: ~15 minutes

### What Gets Created
- Transit Gateway
- VPC attachments (Egress + all clients)
- Route tables and associations
- Flow logs

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/01.5-transit-gateway/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### Validation
```bash
# Check TGW
aws ec2 describe-transit-gateways

# Check attachments
aws ec2 describe-transit-gateway-attachments

# Verify routes
aws ec2 describe-route-tables --filters "Name=vpc-id,Values={client-vpc-id}"
```

📘 [Networking Guide](NETWORKING.md#transit-gateway-architecture)

---

## Layer 02: Platform (EKS)

**Purpose**: Dedicated EKS clusters per client  
**Time**: ~20 minutes

### What Gets Created
- EKS cluster (control plane)
- Managed node groups
- OIDC provider
- Cluster security groups
- CloudWatch log groups

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/02-platform/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig \
  --region us-east-2 \
  --name {client}-production-us-east-2 \
  --alias {client}

# Verify
kubectl get nodes
```

### Configuration
```hcl
# terraform.tfvars
cluster_version          = "1.31"
enable_public_access     = true
management_cidr_blocks   = ["203.0.113.0/24"]
```

📘 [Full Guide](GETTING-STARTED.md#layer-02-platform)

---

## Layer 03: Database

**Purpose**: PostgreSQL master + replica  
**Time**: ~15 minutes

### What Gets Created
- Master PostgreSQL instance
- Read replica
- EBS volumes (data, WAL, backup)
- Database security groups
- CloudWatch alarms

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/03-database/production

# Create secrets file (DO NOT COMMIT!)
cat > database-secrets.tfvars << 'EOF'
database_passwords = {
  "client-name" = "SecurePassword123!"
}
replication_passwords = {
  "client-name" = "ReplicaPassword456!"
}
EOF
chmod 600 database-secrets.tfvars

terraform init -backend-config=backend.hcl
terraform plan -var-file=database-secrets.tfvars
terraform apply -var-file=database-secrets.tfvars
```

### Database Access
```bash
# Get IP
terraform output -json client_databases | jq '.["{client}"]'

# SSH to instance
ssh -i ~/.ssh/key.pem admin@{db-ip}

# Connect to PostgreSQL
psql -U postgres
```

📘 [Full Guide](GETTING-STARTED.md#layer-03-database)

---

## Layer 04: Standalone Compute

**Purpose**: Analytics/batch processing instances  
**Time**: ~5 minutes  
**Optional**: Skip if only using Kubernetes

### What Gets Created
- Analytics EC2 instance
- Data volume
- Security group
- CloudWatch monitoring

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/04-standalone-compute/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

---

## Layer 05: Cluster Services

**Purpose**: Kubernetes controllers (Autoscaler, ALB, DNS, Istio)  
**Time**: ~15 minutes

### What Gets Created
- Cluster Autoscaler
- AWS Load Balancer Controller
- Metrics Server
- ExternalDNS
- Istio Service Mesh
- Route53 hosted zones per client

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/05-cluster-services/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Verify services
kubectl --context {client} get pods -n kube-system
kubectl --context {client} get pods -n istio-system
```

### Configuration
```hcl
# terraform.tfvars
parent_dns_zone         = "xyz.com"
enable_cluster_autoscaler = true
enable_istio_service_mesh = true
istio_version            = "1.27.1"
```

📘 [Full Guide](GETTING-STARTED.md#layer-05-cluster-services)

---

## Layer 06: Observability

**Purpose**: Prometheus, Grafana, Loki, Tempo per client  
**Time**: ~15 minutes

### What Gets Created
- Prometheus (metrics)
- Grafana (dashboards)
- Loki (logs)
- Tempo (traces)
- Fluent Bit (log forwarding)
- AlertManager

### Deployment
```bash
cd providers/aws/regions/us-east-2/layers/06-observability/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Access Grafana
kubectl --context {client} port-forward -n observability svc/grafana 3000:80
# Open: http://localhost:3000
```

### Tier-Based Resources
- **Standard**: 1 Prometheus replica, 50Gi storage, 7-day retention
- **Premium**: 2 Prometheus replicas (HA), 100Gi storage, 15-day retention

📘 [Full Guide](GETTING-STARTED.md#layer-06-observability)

---

## Complete Deployment Script

```bash
#!/bin/bash
# Deploy all layers for a new client

CLIENT="acme-corp"
REGION="us-east-2"
ENV="production"

# Layer 00 (one-time only if not already deployed)
cd providers/aws/regions/${REGION}/layers/00-bootstrap/${ENV}
terraform init && terraform apply -auto-approve

# Layers 01-06
for LAYER in 01-foundation 01.5-transit-gateway 02-platform 03-database 04-standalone-compute 05-cluster-services 06-observability; do
  echo "Deploying ${LAYER}..."
  cd providers/aws/regions/${REGION}/layers/${LAYER}/${ENV}
  terraform init -backend-config=backend.hcl
  terraform apply -auto-approve
done

# Configure kubectl
aws eks update-kubeconfig \
  --region ${REGION} \
  --name ${CLIENT}-${ENV}-${REGION} \
  --alias ${CLIENT}

echo "Deployment complete!"
kubectl get nodes
```

---

## Backend Configuration Files

After Layer 00, each layer needs `backend.hcl`:

```hcl
# Example: layers/01-foundation/production/backend.hcl
bucket         = "terraform-state-us-east-2-production"
key            = "us-east-2/01-foundation/production/terraform.tfstate"
region         = "us-east-2"
encrypt        = true
kms_key_id     = "alias/terraform-state-production"
dynamodb_table = "terraform-state-lock"
```

State keys are organized:
```
us-east-2/01-foundation/production/terraform.tfstate
us-east-2/01.5-transit-gateway/production/terraform.tfstate
us-east-2/02-platform/production/terraform.tfstate
...
```

---

## Post-Deployment Verification

```bash
# 1. Network connectivity
kubectl --context {client} run test --image=nicolaka/netshoot -it --rm -- bash
# Inside: curl -I https://www.google.com

# 2. DNS resolution
dig NS {client}.xyz.com

# 3. Monitoring
kubectl --context {client} port-forward -n observability svc/grafana 3000:80

# 4. Cost tagging
aws ec2 describe-vpcs --vpc-ids {vpc-id} | jq '.Vpcs[].Tags'
```

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Detailed walkthrough
- [Architecture](ARCHITECTURE.md) - Design overview
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
- [Client Configuration](CLIENT-CONFIGURATION.md) - tfvars guide

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
