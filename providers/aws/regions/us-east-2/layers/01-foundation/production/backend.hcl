# =============================================================================
# Backend Configuration: foundation Layer - us-east-2 production
# =============================================================================
# Auto-generated backend configuration for consistent team usage
# Initialize with: terraform init -backend-config=backend.hcl
# =============================================================================

bucket = "ohio-01-terraform-state-production"
key    = "providers/aws/regions/us-east-2/layers/01-foundation/production/terraform.tfstate"
region = "us-east-2"
encrypt = true
dynamodb_table = "terraform-locks-us-east"

# =============================================================================
# Backend Configuration Notes:
# - This file is version controlled for team consistency
# - No user-specific configuration required
# - Works across all platforms (Linux, macOS, Windows)
# - State is stored in S3 with DynamoDB locking
# =============================================================================
