# Backend Configuration for us-east-2 production

Generated automatically on Wed Oct 15 01:11:12 PM EAT 2025 by `provision-s3-infrastructure.sh`.

## Backend Infrastructure

- **S3 Bucket**: `ohio-01-terraform-state-production`
- **DynamoDB Table**: `terraform-locks-us-east`
- **Region**: `us-east-2`
- **Environment**: `production`

## Usage

To use these backend configurations with Terraform:

```bash
# Initialize with foundation layer backend
terraform init -backend-config=../../../../backends/aws/production/us-east-2/foundation.hcl

# Initialize with platform layer backend  
terraform init -backend-config=../../../../backends/aws/production/us-east-2/platform.hcl
```

## Files

- `shared-services.hcl` - Backend config for shared-services layer
- `databases.hcl` - Backend config for databases layer
- `foundation.hcl` - Backend config for foundation layer
- `observability.hcl` - Backend config for observability layer
- `platform.hcl` - Backend config for platform layer
