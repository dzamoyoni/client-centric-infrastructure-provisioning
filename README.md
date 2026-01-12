# Client-Centric Terraform Infrastructure

## Overview

This repository implements a **true client-centric architecture** where each client gets completely isolated infrastructure:
- Dedicated VPC with unique CIDR ranges
- Isolated EKS cluster with dedicated node groups
- Client-specific databases and compute instances
- Per-client observability stack (Prometheus, Grafana, Loki, Tempo)
- Individual Route53 DNS zones under `*.xyz.com`

**Architecture Philosophy**: Each client is an independent entity with zero shared resources, ensuring complete isolation for security, compliance, and cost tracking.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Repository Structure](#repository-structure)
3. [Quick Start: Onboarding a New Client](#quick-start-onboarding-a-new-client)
4. [Detailed Layer Deployment](#detailed-layer-deployment)
5. [Client Configuration](#client-configuration)
6. [Helper Scripts](#helper-scripts)
7. [DNS Management](#dns-management)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
```bash
# Terraform
terraform version  # >= 1.5.0

# AWS CLI
aws --version      # >= 2.x

# kubectl (for EKS management)
kubectl version

# Optional: CIDR validation tools
./scripts/validate-cidr.sh
```

### AWS Credentials
```bash
# Configure AWS credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-2"
```

### Required AWS Permissions
- VPC, Subnet, Route Table, Internet Gateway, NAT Gateway
- EKS Cluster and Node Group management
- EC2 instances, Security Groups, EBS volumes
- S3 buckets and IAM roles/policies
- Route53 hosted zones and records
- CloudWatch logs

---

## Repository Structure

```
client-centric-terraform/
├── providers/
│   └── aws/
│       └── regions/
│           └── us-east-2/
│               └── layers/
│                   ├── 01-foundation/           # VPC, Subnets, NAT, VPN
│                   ├── 02-platform/             # EKS clusters
│                   ├── 03-database/             # PostgreSQL instances
│                   ├── 04-standalone-compute/   # Analytics/batch compute
│                   ├── 05-cluster-services/     # Autoscaler, ALB, ExternalDNS, Istio
│                   └── 06-observability/        # Prometheus, Grafana, Loki, Tempo
├── modules/                                     # Reusable Terraform modules
│   ├── client-vpc/                             # Per-client VPC module
│   ├── eks-platform/                           # EKS cluster module
│   ├── shared-services/                        # Kubernetes controllers
│   ├── istio-service-mesh/                     # Service mesh
│   ├── observability-per-client/               # Monitoring stack
│   └── tagging/                                # Centralized tagging
├── scripts/                                     # Helper automation scripts
│   ├── provision-s3-client-centric.sh          # S3 backend & observability setup
│   ├── validate-cidr.sh                        # CIDR conflict detection
│   ├── destroy-s3-buckets.sh                   # S3 cleanup (DANGEROUS)
│   ├── verify-s3-security.sh                   # Security audit for S3
│   └── emergency-s3-cleanup.sh                 # Emergency cleanup script
└── docs/                                        # Additional documentation
```

---

## Quick Start: Onboarding a New Client

### Step 1: Define the New Client

Edit `providers/aws/regions/us-east-2/layers/*/production/clients.auto.tfvars`:

```hcl
clients = {
  # Existing clients...
  
  "new-client-name" = {
    enabled     = true
    client_code = "NEWCLIENT"
    tier        = "standard"  # or "premium"
    
    network = {
      vpc_cidr    = "10.X.0.0/16"    # Must be globally unique!
      cidr_offset = X                 # Used for subnet calculations
    }
    
    eks = {
      enabled        = true
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 5
      desired_size   = 2
      disk_size      = 50
      capacity_type  = "ON_DEMAND"   # or "SPOT"
    }
    
    compute = {
      analytics_enabled = true        # Optional: analytics instance
      instance_type     = "t3.large"
      root_volume_size  = 30
      data_volume_size  = 100
    }
    
    storage = {
      enable_dedicated_buckets = true
      backup_retention_days    = 30
    }
    
    security = {
      database_ports = [5432, 5433]  # PostgreSQL ports
      custom_ports   = [8080, 9090]  # Application ports
    }
    
    vpn = {
      enabled              = false    # Set true if client needs VPN
      customer_gateway_ip  = "X.X.X.X"
      bgp_asn             = 65001
      amazon_side_asn     = 64512
      static_routes_only  = true
      local_network_cidr  = "192.168.0.0/24"
      tunnel1_inside_cidr = "169.254.10.0/30"
      tunnel2_inside_cidr = "169.254.11.0/30"
      description         = "VPN to client datacenter"
    }
    
    metadata = {
      full_name     = "New Client Full Name"
      industry      = "Technology"
      contact_email = "ops@newclient.com"
      compliance    = ["SOC2", "ISO27001"]
      cost_center   = "CC-NEWCLIENT-001"
      business_unit = "Enterprise"
    }
  }
}
```

** Important**: Each client MUST have a unique VPC CIDR range. Use the CIDR validation script to prevent conflicts:

```bash
./scripts/validate-cidr.sh
```

### Step 2: Validate CIDR Registry

Update `cidr-registry.yaml` at the repository root:

```yaml
clients:
  new-client-name:
    vpc_cidr: "10.X.0.0/16"
    region: "us-east-2"
    environment: "production"
    allocated_date: "2026-01-05"
    notes: "New client onboarding"
```

### Step 3: Provision S3 Backend and Observability Buckets

**Before deploying any Terraform layers**, create the S3 buckets for state storage and observability:

```bash
# Run the S3 provisioning script
cd /home/dennis.juma/client-centric-terraform

./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01

# This creates:
# - ohio-01-terraform-state-production (backend state)
# - ohio-01-us-east-2-logs-production (observability logs)
# - ohio-01-us-east-2-traces-production (distributed traces)
# - ohio-01-us-east-2-metrics-production (Prometheus metrics)
# - ohio-01-us-east-2-audit-logs-production (audit logs)
# - terraform-locks-us-east (DynamoDB table for state locking)
```

### Step 4: Deploy Infrastructure Layers

Deploy in order (each layer depends on the previous):

```bash
# 1. Foundation Layer (VPC, Subnets, NAT)

cd providers/aws/regions/us-east-2/layers/01-foundation/production
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 2. Platform Layer (EKS Clusters)
cd ../02-platform/production
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 3. Database Layer (PostgreSQL)
cd ../03-database/production
terraform init -backend-config=backend.hcl
terraform plan -var-file=database-secrets.tfvars  # Contains passwords
terraform apply -var-file=database-secrets.tfvars

# 4. Standalone Compute Layer (Analytics instances)
cd ../04-standalone-compute/production
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 5. Cluster Services Layer (Autoscaler, ALB, DNS, Istio)
cd ../05-cluster-services/production
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 6. Observability Layer (Prometheus, Grafana, Loki)
cd ../06-observability/production
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

---

## Detailed Layer Deployment

### Step 0: S3 Backend Provisioning (One-time Setup)

**Purpose**: Creates S3 buckets and DynamoDB table for Terraform state storage and observability data.

**This must be done BEFORE deploying any Terraform layers.**

#### Using the Provisioning Script

```bash
# Navigate to project root
cd /home/dennis.juma/client-centric-terraform

# Run provisioning script
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01

# Dry-run mode (see what would be created)
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --dry-run

# Create only backend infrastructure
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --backend-only

# Create only observability buckets
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --observability-only
```

#### What Gets Created

**Backend Infrastructure** (shared across all clients):
- **S3 Bucket**: `ohio-01-terraform-state-production`
  - Versioning: Enabled
  - Encryption: AES256
  - Public Access: Blocked
  - Purpose: Stores Terraform state for all clients
  
- **DynamoDB Table**: `terraform-locks-us-east`
  - Billing: Pay-per-request
  - Purpose: State file locking to prevent concurrent modifications

**Observability Infrastructure** (shared with client prefixes):
- **Logs Bucket**: `ohio-01-us-east-2-logs-production`
  - Structure: `logs/client={client}/...`
  - Retention: 90 days
  
- **Traces Bucket**: `ohio-01-us-east-2-traces-production`
  - Structure: `traces/client={client}/...`
  - Retention: 30 days
  
- **Metrics Bucket**: `ohio-01-us-east-2-metrics-production`
  - Structure: `metrics/client={client}/...`
  - Retention: 90 days
  
- **Audit Logs Bucket**: `ohio-01-us-east-2-audit-logs-production`
  - Structure: `audit-logs/client={client}/...`
  - Retention: 7 years (compliance)

#### Bucket Naming Convention

```
Backend:       {project}-terraform-state-{environment}
Observability: {project}-{region}-{type}-{environment}
DynamoDB:      terraform-locks-{region-short}
```

#### Backend Configuration Files

After provisioning, each layer has a `backend.hcl` file:

```hcl
# Example: layers/01-foundation/production/backend.hcl
bucket         = "ohio-01-terraform-state-production"
key            = "providers/aws/regions/us-east-2/layers/01-foundation/production/terraform.tfstate"
region         = "us-east-2"
encrypt        = true
dynamodb_table = "terraform-locks-us-east"
```

The state keys are organized per layer and environment:
```
providers/aws/regions/us-east-2/layers/01-foundation/production/terraform.tfstate
providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfstate
providers/aws/regions/us-east-2/layers/03-database/production/terraform.tfstate
...
```

---

### Layer 01: Foundation (Networking)

**Purpose**: Creates per-client VPCs with complete network isolation.

**Resources Created Per Client**:
- VPC with custom CIDR range
- Public subnets (2 AZs) with Internet Gateway
- Private subnets (2 AZs) with NAT Gateways
- EKS-specific subnets with proper tags
- Security Groups (EKS, Database, Compute)
- VPC Flow Logs to CloudWatch
- Optional Site-to-Site VPN connection

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/01-foundation/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Key Configuration Files**:
- `terraform.tfvars`: Common settings (region, environment)
- `clients.auto.tfvars`: Per-client network configuration
- `main.tf`: VPC module calls per client

**Naming Convention**:
- VPC: `{client}-{environment}-vpc`
- Subnets: `{client}-{environment}-{public|private|eks}-{az}`
- NAT Gateways: `{client}-{environment}-nat-{az}`

**Validation**:
```bash
# Check VPC creation
aws ec2 describe-vpcs --filters "Name=tag:Client,Values=new-client-name"

# Check subnets
aws ec2 describe-subnets --filters "Name=tag:Client,Values=new-client-name"
```

---

### Layer 02: Platform (EKS Clusters)

**Purpose**: Creates dedicated EKS clusters for each client.

**Resources Created Per Client**:
- EKS Cluster (Kubernetes control plane)
- Managed Node Groups with auto-scaling
- Cluster IAM roles and OIDC provider
- Cluster security groups
- CloudWatch log groups for audit logs

**Cluster Naming**: `{client}-{environment}-{region}`
- Example: `new-client-name-production-us-east-2`

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/02-platform/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Configure kubectl access
aws eks update-kubeconfig \
  --region us-east-2 \
  --name new-client-name-production-us-east-2 \
  --alias new-client-name

# Verify cluster
kubectl get nodes
```

**Key Configuration**:
- Kubernetes version: Set in `terraform.tfvars`
- Node instance types: Defined per client in `clients.auto.tfvars`
- Cluster endpoint access: Public or private

**Troubleshooting**:
```bash
# Check cluster status
aws eks describe-cluster --name {cluster-name} --region us-east-2

# View node group
aws eks describe-nodegroup \
  --cluster-name {cluster-name} \
  --nodegroup-name {nodegroup-name} \
  --region us-east-2
```

---

### Layer 03: Database (PostgreSQL)

**Purpose**: Deploys PostgreSQL instances on EC2 with master-replica setup.

**Resources Created Per Client**:
- Master PostgreSQL instance
- Read replica instance
- Dedicated EBS volumes (data, WAL, backup)
- Database security groups
- CloudWatch alarms for monitoring

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/03-database/production

# Create secrets file (never commit to git!)
cat > database-secrets.tfvars << EOF
database_passwords = {
  "new-client-name" = "SecurePassword123!"
}

replication_passwords = {
  "new-client-name" = "ReplicaPassword456!"
}
EOF

terraform init -backend-config=backend.hcl
terraform plan -var-file=database-secrets.tfvars
terraform apply -var-file=database-secrets.tfvars
```

**Configuration**:
- AMI: Debian 13 (defined in `terraform.tfvars`)
- Instance types: Memory-optimized (r5/r6i family)
- Volume sizes: Configurable per client
- Backup retention: 7-35 days

**Database Access**:
```bash
# Get database instance IP
terraform output -json client_databases | jq '.["new-client-name"]'

# SSH to instance (using key pair)
ssh -i ~/.ssh/your-key.pem admin@{master-ip}

# Connect to PostgreSQL
psql -U postgres
```

---

### Layer 04: Standalone Compute (Analytics)

**Purpose**: Provisions compute instances for data processing and analytics.

**Resources Created Per Client** (if enabled):
- Analytics EC2 instance (Debian 13)
- Data volume for processing
- Security group for custom ports
- CloudWatch monitoring

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/04-standalone-compute/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Use Cases**:
- Batch data processing
- ETL jobs
- Machine learning workloads
- Legacy applications not suitable for Kubernetes

---

### Layer 05: Cluster Services (Kubernetes Controllers)

**Purpose**: Installs essential Kubernetes services in each client's EKS cluster.

**Services Deployed Per Client**:
1. **Cluster Autoscaler**: Automatically scales node groups
2. **AWS Load Balancer Controller**: Manages ALB/NLB from Kubernetes
3. **Metrics Server**: Provides resource metrics for HPA
4. **External DNS**: Automatically creates Route53 records
5. **Istio Service Mesh**: Advanced traffic management (ambient mode)

**Route53 DNS Architecture**:
- Parent zone: `ezra.world`
- Per-client subdomain: `{client}.ezra.world`
- Example: `new-client-name.ezra.world`

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/05-cluster-services/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Verify services
kubectl --context new-client-name get pods -n kube-system
kubectl --context new-client-name get pods -n istio-system
```

**Configuration**:
- Service versions: Set in `terraform.tfvars`
- Autoscaler settings: Scale-down delay, node utilization thresholds
- Istio: Ambient mode, ingress gateway replicas, observability integration

**DNS Setup**:
```bash
# Verify Route53 zone creation
aws route53 list-hosted-zones | grep new-client-name

# Test DNS resolution (after deploying an ingress)
kubectl --context new-client-name apply -f - << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    external-dns.alpha.kubernetes.io/hostname: test.new-client-name.ezra.world
spec:
  rules:
  - host: test.new-client-name.ezra.world
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service
            port:
              number: 80
EOF
```

---

### Layer 06: Observability (Monitoring & Logging)

**Purpose**: Deploys complete observability stack per client.

**Stack Per Client**:
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization dashboards
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Fluent Bit**: Log forwarding
- **AlertManager**: Alert routing

**Storage**:
- S3 buckets for long-term storage: `{region}-{environment}-{logs|traces|metrics}`
- Client-specific prefixes: `{client}/`
- Persistent volumes for short-term caching

**Deployment**:
```bash
cd providers/aws/regions/us-east-2/layers/06-observability/production

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# Access Grafana (port-forward)
kubectl --context new-client-name port-forward -n observability svc/grafana 3000:80

# Open browser: http://localhost:3000
# Default credentials: admin / {set in terraform.tfvars}
```

**Tier-Based Resources**:
- **Standard Tier**:
  - Prometheus: 1 replica, 50Gi storage, 7-day retention
  - Grafana: 20Gi storage
  - Loki: 7-day log retention
  
- **Premium Tier**:
  - Prometheus: 2 replicas (HA), 100Gi storage, 15-day retention
  - Grafana: 50Gi storage
  - Loki: 30-day log retention

**Configuration**:
- Retention periods: `terraform.tfvars`
- Alert destinations: Email and Slack
- Remote write: Optional for central Prometheus

---

## Client Configuration

### Main Configuration Files

#### 1. `clients.auto.tfvars` (All Layers)

This is the **single source of truth** for client definitions. Each layer reads the same file.

**Location**: `providers/aws/regions/us-east-2/layers/*/production/clients.auto.tfvars`

**Structure**:
```hcl
clients = {
  "client-name" = {
    enabled     = true           # Master switch
    client_code = "CODE"         # Short identifier
    tier        = "standard"     # Affects resource allocation
    
    network = { ... }            # VPC configuration
    eks = { ... }                # Kubernetes settings
    compute = { ... }            # Standalone instances
    storage = { ... }            # S3 and backup settings
    security = { ... }           # Firewall rules
    vpn = { ... }                # Optional VPN
    metadata = { ... }           # Business information
  }
}
```

**Best Practices**:
- Copy file consistently across all layers
- Use symlinks or Git submodules to avoid drift
- Version control all changes
- Validate CIDR uniqueness before adding clients

#### 2. `terraform.tfvars` (Per Layer)

Layer-specific configuration shared across all clients.

**Layer 01 (Foundation)**:
```hcl
environment = "production"
region      = "us-east-2"
sns_topic_arn = "arn:aws:sns:us-east-2:123456789012:alerts"
```

**Layer 02 (Platform)**:
```hcl
environment              = "production"
region                   = "us-east-2"
cluster_version          = "1.31"
enable_public_access     = true
management_cidr_blocks   = ["203.0.113.0/24"]  # Your IP range
terraform_state_bucket   = "us-east-2-production-terraform-state"
terraform_state_region   = "us-east-2"
```

**Layer 05 (Cluster Services)**:
```hcl
environment = "production"
region      = "us-east-2"

# Service enablement
enable_cluster_autoscaler           = true
enable_aws_load_balancer_controller = true
enable_metrics_server               = true
enable_external_dns                 = true
enable_istio_service_mesh           = true

# Service versions
cluster_autoscaler_version           = "9.37.0"
aws_load_balancer_controller_version = "1.8.1"
istio_version                        = "1.27.1"

# DNS configuration
parent_dns_zone         = "ezra.world"
create_root_placeholder = true
```

---

## Helper Scripts

### 1. S3 Provisioning Script

**Purpose**: Creates S3 backend and observability buckets with proper security.

**Location**: `scripts/provision-s3-client-centric.sh`

**Usage**:
```bash
# Create all infrastructure
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01

# Dry-run mode (preview only)
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --dry-run

# Backend only (state storage)
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --backend-only

# Observability buckets only
./scripts/provision-s3-client-centric.sh \
  --region us-east-2 \
  --environment production \
  --project-name ohio-01 \
  --observability-only
```

**Features**:
- Client-centric bucket structure with prefixes
- Automatic versioning and encryption (AES256)
- Public access blocking
- DynamoDB table for state locking
- Validates AWS credentials before proceeding
- Interactive confirmation (use `--force` to skip)

**What Gets Created**:
- 1 S3 bucket for Terraform state (shared across all clients)
- 4 S3 buckets for observability (logs, traces, metrics, audit)
- 1 DynamoDB table for state locking
- Total: 5 buckets + 1 table

---

### 2. CIDR Validation Script

**Purpose**: Prevents CIDR conflicts across clients.

**Location**: `scripts/validate-cidr.sh`

**Usage**:
```bash
# Validate CIDR registry
./scripts/validate-cidr.sh

# Output:
# [INFO] Validating CIDR registry: /path/to/cidr-registry.yaml
# [INFO] Found 3 client VPC CIDRs
# [INFO] ✓ Valid CIDR: 10.100.0.0/16
# [INFO] ✓ Valid CIDR: 10.101.0.0/16
# [INFO] ✓ Valid CIDR: 10.102.0.0/16
# [SUCCESS] No duplicate CIDRs found
# [SUCCESS] All CIDRs have valid format
# [SUCCESS] CIDR Registry Validation: PASSED
```

**Integration**:
```bash
# Add to pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
./scripts/validate-cidr.sh || exit 1
EOF
chmod +x .git/hooks/pre-commit
```

**Validation Checks**:
- Duplicate CIDR detection
- CIDR format validation (xxx.xxx.xxx.xxx/xx)
- Reserved range verification
- Cross-client overlap detection

---

### 3. S3 Security Verification Script

**Purpose**: Audits S3 buckets for security compliance.

**Location**: `scripts/verify-s3-security.sh`

**Usage**:
```bash
# Verify all infrastructure buckets
./scripts/verify-s3-security.sh

# Output:
# [INFO] Finding S3 buckets related to our infrastructure...
# [SUCCESS] Found 5 bucket(s) to verify
# ╭─ Verifying bucket: ohio-01-terraform-state-production
# [INFO] Checking Public Access Block...
# [SUCCESS] ✓ Public Access Block: ENABLED (All 4 settings active)
# [INFO] Checking Server-Side Encryption...
# [SUCCESS] ✓ Server-Side Encryption: ENABLED (AES256)
# [INFO] Checking Versioning...
# [SUCCESS] ✓ Versioning: ENABLED
# ...
```

**Security Checks**:
1. Public Access Block (all 4 settings)
2. Server-Side Encryption (AES256 or KMS)
3. Versioning status
4. Bucket policy for public access
5. Object ownership controls
6. Access logging configuration
7. ACL for public grants
8. CloudWatch metrics enablement

---

### 4. S3 Bucket Destruction Script

**Purpose**: Safely destroys S3 buckets and all contents.

**Location**: `scripts/destroy-s3-buckets.sh`

⚠️ **DANGER**: This script permanently deletes data!

**Usage**:
```bash
# Destroy all buckets (with confirmation)
./scripts/destroy-s3-buckets.sh \
  --region us-east-2 \
  --environment production \
  --type all

# Destroy specific bucket type
./scripts/destroy-s3-buckets.sh \
  --region us-east-2 \
  --type logs

# Destroy specific bucket by name
./scripts/destroy-s3-buckets.sh \
  --bucket ohio-01-us-east-2-logs-production

# Dry-run mode
./scripts/destroy-s3-buckets.sh \
  --type all \
  --dry-run

# Force delete with backup
./scripts/destroy-s3-buckets.sh \
  --type all \
  --force \
  --backup
```

**Features**:
- Handles versioned objects and delete markers
- Cleans up multipart uploads
- Handles cross-region replication
- Optional backup before deletion
- Multiple confirmation prompts
- Backend state bucket protection

**Bucket Types**:
- `logs`: Application and system logs
- `traces`: Distributed traces
- `metrics`: Prometheus metrics
- `audit_logs`: Kubernetes audit logs
- `backend-state`: Terraform state (EXTRA PROTECTION)
- `all`: All infrastructure buckets

---

### 5. Emergency S3 Cleanup Script

**Purpose**: Emergency cleanup for stuck or corrupted buckets.

**Location**: `scripts/emergency-s3-cleanup.sh`

⚠️ **USE WITH EXTREME CAUTION**

**Usage**:
```bash
# Only use when normal destroy fails
./scripts/emergency-s3-cleanup.sh \
  --bucket ohio-01-us-east-2-logs-production
```

**When to Use**:
- Normal destroy script fails
- Buckets in inconsistent state
- Stuck multipart uploads
- Versioning issues
- Replication conflicts

---

## DNS Management

### Architecture

```
ezra.world (parent zone)
├── new-client-name.ezra.world (delegated zone)
│   ├── app.new-client-name.ezra.world
│   ├── api.new-client-name.ezra.world
│   └── *.new-client-name.ezra.world
├── another-client.ezra.world
└── ...
```

### Setting Up Parent Zone (One-time)

```bash
# Create parent zone in Route53
aws route53 create-hosted-zone \
  --name ezra.world \
  --caller-reference $(date +%s)

# Update domain registrar with AWS name servers
aws route53 get-hosted-zone --id {zone-id} | jq '.DelegationSet.NameServers'
```

### Per-Client Zone (Automatic)

Terraform automatically creates and delegates zones when deploying Layer 05:

```bash
cd providers/aws/regions/us-east-2/layers/05-cluster-services/production
terraform apply

# Verify delegation
dig NS new-client-name.ezra.world
```

### Creating DNS Records (Automatic via ExternalDNS)

Deploy a Kubernetes Service or Ingress with annotation:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: my-app.new-client-name.ezra.world
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

ExternalDNS automatically creates the A record pointing to the load balancer.

### Manual DNS Records

```bash
# Get zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name new-client-name.ezra.world \
  --query 'HostedZones[0].Id' \
  --output text)

# Create record
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "manual.new-client-name.ezra.world",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "target.example.com"}]
      }
    }]
  }'
```

---

## Troubleshooting

### Common Issues

#### 1. CIDR Conflicts

**Symptom**: Terraform fails with VPC peering or routing errors.

**Solution**:
```bash
# Run validation
./scripts/validate-cidr.sh

# Update conflicting client
vim providers/aws/regions/us-east-2/layers/01-foundation/production/clients.auto.tfvars

# Destroy and recreate (only if not in production!)
terraform destroy -target='module.client_vpcs["client-name"]'
terraform apply
```

#### 2. EKS Cluster Unreachable

**Symptom**: `kubectl` commands timeout.

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-2 \
  --name {cluster-name}

# Check security groups
aws eks describe-cluster --name {cluster-name} \
  | jq '.cluster.resourcesVpcConfig.clusterSecurityGroupId'

# Verify your IP is in management_cidr_blocks
```

#### 3. State Lock Issues

**Symptom**: "Error acquiring the state lock"

**Solution**:
```bash
# Check lock in DynamoDB
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution!)
terraform force-unlock {lock-id}
```

#### 4. Node Group Not Scaling

**Symptom**: Pods stuck in Pending state.

**Solution**:
```bash
# Check cluster autoscaler logs
kubectl --context {client} logs -n kube-system \
  -l app.kubernetes.io/name=cluster-autoscaler

# Verify IAM permissions
aws iam get-role-policy --role-name {autoscaler-role} \
  --policy-name {policy-name}

# Check node group limits
aws eks describe-nodegroup \
  --cluster-name {cluster-name} \
  --nodegroup-name {nodegroup-name}
```

#### 5. DNS Not Resolving

**Symptom**: `nslookup app.client.ezra.world` fails.

**Solution**:
```bash
# Check ExternalDNS logs
kubectl --context {client} logs -n kube-system \
  -l app.kubernetes.io/name=external-dns

# Verify Route53 zone
aws route53 list-resource-record-sets \
  --hosted-zone-id {zone-id}

# Check service annotation
kubectl --context {client} get svc {service-name} -o yaml \
  | grep external-dns
```

---

## Maintenance Operations

### Upgrading Kubernetes Version

```bash
# Update version in terraform.tfvars
vim providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfvars
# Change: cluster_version = "1.32"

# Plan upgrade
cd providers/aws/regions/us-east-2/layers/02-platform/production
terraform plan

# Apply (will trigger rolling update)
terraform apply

# Update kubeconfig
aws eks update-kubeconfig --name {cluster-name}

# Verify nodes
kubectl get nodes
```

### Scaling Client Resources

```bash
# Update desired capacity in clients.auto.tfvars
vim clients.auto.tfvars
# Change: eks.desired_size = 5

# Apply changes
terraform plan
terraform apply

# Monitor scaling
kubectl get nodes --watch
```

### Backup and Disaster Recovery

**State Files**:
```bash
# Automatic S3 versioning is enabled
# Restore previous version:
aws s3api list-object-versions \
  --bucket {state-bucket} \
  --prefix providers/aws/regions/us-east-2/layers/

# Download specific version
aws s3api get-object \
  --bucket {state-bucket} \
  --key {state-key} \
  --version-id {version-id} \
  terraform.tfstate.backup
```

**Database Backups**:
```bash
# Automated EBS snapshots configured
# Manual snapshot:
aws ec2 create-snapshot \
  --volume-id {volume-id} \
  --description "Manual backup for client-name"
```

---

## Security Best Practices

1. **Never commit secrets**:
   ```bash
   # Add to .gitignore
   echo "*secrets*.tfvars" >> .gitignore
   echo "*.pem" >> .gitignore
   ```

2. **Use AWS Secrets Manager** for sensitive data:
   ```bash
   aws secretsmanager create-secret \
     --name /terraform/client-name/db-password \
     --secret-string "{\"password\":\"SecurePass123!\"}"
   ```

3. **Enable MFA** for Terraform operations:
   ```bash
   # Use AWS CLI with MFA
   aws sts get-session-token --serial-number {mfa-arn} --token-code {code}
   ```

4. **Restrict state bucket access**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {"AWS": "arn:aws:iam::{account}:role/TerraformRole"},
       "Action": ["s3:GetObject", "s3:PutObject"],
       "Resource": "arn:aws:s3:::{bucket}/providers/aws/*"
     }]
   }
   ```

5. **Regular security audits**:
   ```bash
   # Check for open security groups
   aws ec2 describe-security-groups \
     --filters "Name=ip-permission.cidr,Values=0.0.0.0/0"
   
   # Review IAM policies
   aws iam get-account-authorization-details > iam-audit.json
   ```

---

## Cost Optimization

### Per-Client Cost Tracking

All resources are tagged with:
- `Client`: Client name
- `CostCenter`: From client metadata
- `Environment`: production/staging/dev

**Generate cost reports**:
```bash
# AWS Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Client

# Or use built-in script
./scripts/cost-report.sh --client new-client-name --month 2026-01
```

### Optimization Strategies

1. **Use Spot Instances** for non-production:
   ```hcl
   capacity_type = "SPOT"  # in clients.auto.tfvars
   ```

2. **Enable Cluster Autoscaler** scale-down:
   ```hcl
   cluster_autoscaler_scale_down_enabled = true
   cluster_autoscaler_scale_down_unneeded_time = "5m"
   ```

3. **S3 Lifecycle Policies** (automatically configured):
   - Logs → Glacier after 90 days
   - Traces → Delete after 30 days

4. **Right-size instances**:
   ```bash
   # Analyze resource usage
   kubectl top nodes
   kubectl top pods --all-namespaces
   
   # Adjust instance types in clients.auto.tfvars
   ```

---

## Support and Contact

### Documentation
- **Architecture Diagrams**: `docs/architecture/`
- **Runbooks**: `docs/runbooks/`
- **Change Log**: `CHANGELOG.md`

### Getting Help
- Internal Wiki: https://wiki.company.com/terraform
- Slack Channel: #platform-engineering
- On-call: PagerDuty rotation

### Contributing
1. Create feature branch: `git checkout -b feature/new-client-onboarding`
2. Make changes and test thoroughly
3. Run validation: `./scripts/validate-all.sh`
4. Submit pull request with description
5. Tag reviewers from platform team

---

## Appendix

### Environment Variables Reference

```bash
# AWS Configuration
export AWS_REGION="us-east-2"
export AWS_PROFILE="terraform"
export AWS_DEFAULT_OUTPUT="json"

# Terraform Configuration
export TF_VAR_environment="production"
export TF_LOG="INFO"                    # DEBUG for troubleshooting
export TF_LOG_PATH="terraform.log"

# Custom Scripts
export CLIENT_NAME="new-client-name"
export CIDR_REGISTRY="./cidr-registry.yaml"
```

### Useful Commands Cheat Sheet

```bash
# Quick client status
for client in $(terraform output -json clients | jq -r 'keys[]'); do
  echo "=== $client ==="
  kubectl --context $client get nodes
  kubectl --context $client get pods --all-namespaces | grep -v Running
done

# Force refresh state
terraform refresh

# Show resource graph
terraform graph | dot -Tpng > graph.png

# Import existing resource
terraform import 'module.client_vpcs["client"].aws_vpc.this' vpc-12345678

# Targeted destroy
terraform destroy -target='module.client_databases["client"]'

# List all workspaces (if using workspaces)
terraform workspace list
```

### Architecture Decision Records (ADRs)

Key design decisions documented in `docs/adr/`:
- **ADR-001**: Client-Centric vs Multi-Tenant Architecture
- **ADR-002**: Client Naming Conventions
- **ADR-003**: State Management Strategy
- **ADR-004**: DNS Hierarchy Design
- **ADR-005**: Per-Client vs Shared Observability

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────────┐
│              CLIENT ONBOARDING CHECKLIST                    │
├─────────────────────────────────────────────────────────────────────┤
│ ONE-TIME SETUP (if not already done):                       │
│ □ 0. Run provision-s3-client-centric.sh for S3 backend   │
│                                                               │
│ PER-CLIENT ONBOARDING:                                       │
│ □ 1. Allocate unique VPC CIDR (10.X.0.0/16)               │
│ □ 2. Update clients.auto.tfvars in all layers             │
│ □ 3. Update cidr-registry.yaml                            │
│ □ 4. Run ./scripts/validate-cidr.sh                       │
│ □ 5. Deploy Layer 01 (Foundation - VPC)                   │
│ □ 6. Deploy Layer 02 (Platform - EKS)                     │
│ □ 7. Create database-secrets.tfvars                       │
│ □ 8. Deploy Layer 03 (Database - PostgreSQL)              │
│ □ 9. Deploy Layer 04 (Compute) - if needed                │
│ □ 10. Deploy Layer 05 (Cluster Services)                  │
│ □ 11. Verify DNS zone delegation                          │
│ □ 12. Deploy Layer 06 (Observability)                     │
│ □ 13. Configure kubectl context                           │
│ □ 14. Run ./scripts/verify-s3-security.sh                 │
│ □ 15. Test sample application deployment                  │
│ □ 16. Verify monitoring dashboards                        │
│ □ 17. Update documentation with client details            │
│ □ 18. Notify client with access credentials               │
└─────────────────────────────────────────────────────────────────────┘

EMERGENCY CONTACTS:
  Platform Team: infraops@ezra.world
  On-Call: +254***
  PagerDuty: https://ezra.world
```

---

**Last Updated**: January 5, 2026  
**Version**: 1.0.0  
**Maintained By**: Platform Engineering Team
