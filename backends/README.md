# Backend State Management - Client-Centric Architecture

## Overview

This directory contains Terraform backend configurations organized for multi-client, multi-region, multi-cloud infrastructure.

## State Organization Strategy

### **Shared State with Client Prefixes** (Recommended)

We use a **shared S3 bucket per environment** with structured state keys that include client information. This approach provides:

- ✅ Cost efficiency (one bucket vs. hundreds)
- ✅ Operational simplicity (centralized management)
- ✅ Client isolation via IAM policies and key prefixes
- ✅ Blast radius containment (layer-specific state)

### State Key Pattern

```
providers/{provider}/regions/{region}/clients/{client}/layers/{layer}/terraform.tfstate
```

#### Examples:
```
providers/aws/regions/us-east-2/clients/est-test-a/layers/04-standalone-compute/terraform.tfstate
providers/aws/regions/us-east-2/clients/est-test-b/layers/04-standalone-compute/terraform.tfstate
providers/aws/regions/us-east-2/shared/layers/01-foundation/terraform.tfstate
providers/aws/regions/us-east-2/shared/layers/02-platform/terraform.tfstate
```

## Directory Structure

```
backends/
├── aws/
│   ├── production/
│   │   ├── us-east-2/
│   │   │   ├── foundation.hcl           # Shared foundation layer
│   │   │   ├── platform.hcl             # Shared platform layer (EKS)
│   │   │   ├── shared-services.hcl      # Shared services
│   │   │   ├── observability.hcl        # Shared observability
│   │   │   └── clients/
│   │   │       ├── est-test-a.hcl       # Client-specific resources
│   │   │       ├── est-test-b.hcl
│   │   │       └── ...
│   │   └── us-west-2/
│   ├── staging/
│   └── global/
├── azure/
├── gcp/
└── templates/
```

## Backend Configuration Types

### 1. **Shared Infrastructure Layers** (Foundation, Platform, Shared Services)

State files for infrastructure shared across all clients.

**Example: `backends/aws/production/us-east-2/foundation.hcl`**
```hcl
bucket         = "ohio-01-terraform-state-production"
key            = "providers/aws/regions/us-east-2/shared/layers/01-foundation/terraform.tfstate"
region         = "us-east-2"
encrypt        = true
dynamodb_table = "terraform-locks-us-east"
```

### 2. **Client-Specific Layers** (Compute, Databases, Applications)

State files for client-isolated resources.

**Example: `backends/aws/production/us-east-2/clients/est-test-a.hcl`**
```hcl
bucket         = "ohio-01-terraform-state-production"
key            = "providers/aws/regions/us-east-2/clients/est-test-a/layers/04-standalone-compute/terraform.tfstate"
region         = "us-east-2"
encrypt        = true
dynamodb_table = "terraform-locks-us-east"
```

## Usage

### Initializing a Shared Layer

```bash
cd terraform/providers/aws/regions/us-east-2/layers/01-foundation/production
terraform init -backend-config=../../../../../../backends/aws/production/us-east-2/foundation.hcl
```

### Initializing a Client-Specific Layer

```bash
cd terraform/providers/aws/regions/us-east-2/layers/04-standalone-compute/production
terraform init -backend-config=../../../../../../backends/aws/production/us-east-2/clients/est-test-a.hcl
```

## State Isolation & Security

### IAM Policy for Client-Specific Access

Optionally, restrict client access to their own state:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::ohio-01-terraform-state-production/providers/aws/regions/*/clients/est-test-a/*"
    }
  ]
}
```

## S3 Bucket Organization

### Logical State Key Structure

```
ohio-01-terraform-state-production/
├── providers/
│   └── aws/
│       └── regions/
│           └── us-east-2/
│               ├── shared/
│               │   └── layers/
│               │       ├── 01-foundation/
│               │       │   └── terraform.tfstate
│               │       ├── 02-platform/
│               │       │   └── terraform.tfstate
│               │       └── 05-shared-services/
│               │           └── terraform.tfstate
│               └── clients/
│                   ├── est-test-a/
│                   │   └── layers/
│                   │       ├── 03-database-layer/
│                   │       │   └── terraform.tfstate
│                   │       └── 04-standalone-compute/
│                   │           └── terraform.tfstate
│                   └── est-test-b/
│                       └── layers/
│                           ├── 03-database-layer/
│                           │   └── terraform.tfstate
│                           └── 04-standalone-compute/
│                               └── terraform.tfstate
```

## Backend State Best Practices

1. **Enable Versioning**: All state buckets have versioning enabled for recovery
2. **Enable Encryption**: Server-side encryption (AES-256 or KMS) is mandatory
3. **DynamoDB Locking**: Prevents concurrent modifications
4. **Least Privilege IAM**: Grant minimal permissions per client
5. **State Locking**: Always use DynamoDB table for state locking
6. **Regular Backups**: Automated S3 versioning provides point-in-time recovery

## Adding a New Client

1. **Create client backend config** (automatic via script):
   ```bash
   ./scripts/generate-client-backend.sh est-test-c us-east-2 production
   ```

2. **Or manually create**: `backends/aws/production/us-east-2/clients/est-test-c.hcl`

3. **Initialize client layer**:
   ```bash
   terraform init -backend-config=<path-to-backend-config>
   ```

## Migration from Old Structure

If migrating from hardcoded backends to client-centric:

```bash
# 1. Initialize with new backend config
terraform init -backend-config=new-backend.hcl -reconfigure

# 2. Terraform will prompt to migrate state
# 3. Verify state migration
terraform state list
```

## Troubleshooting

### State Lock Conflicts

```bash
# View locks
aws dynamodb scan --table-name terraform-locks-us-east --region us-east-2

# Force unlock (use with caution!)
terraform force-unlock <lock-id>
```

### State File Recovery

```bash
# List versions
aws s3api list-object-versions --bucket ohio-01-terraform-state-production --prefix providers/aws/regions/us-east-2/clients/est-test-a/

# Restore specific version
aws s3api get-object --bucket ohio-01-terraform-state-production \\
  --key providers/aws/regions/us-east-2/clients/est-test-a/layers/04-standalone-compute/terraform.tfstate \\
  --version-id <version-id> restored-state.tfstate
```

## Monitoring & Auditing

- **S3 Access Logs**: Enabled on all state buckets
- **CloudTrail**: Tracks all state file access
- **EventBridge**: Alerts on state file modifications
- **CloudWatch Metrics**: Monitors state file size and access patterns
