# =============================================================================
# Backend Configuration: Layer 01-Foundation
# =============================================================================
# Usage: terraform init -backend-config=backend.hcl
# =============================================================================

bucket         = "terraform-state-us-east-2-production-myorg"
key            = "us-east-2/01-foundation/production/terraform.tfstate"
region         = "us-east-2"
dynamodb_table = "terraform-locks-us-east-2-production"
encrypt        = true
kms_key_id     = "alias/terraform-state-production"
