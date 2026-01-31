# =============================================================================
# Backend Configuration: Layer 06-Observability
# =============================================================================
# Usage: terraform init -backend-config=backend.hcl
# =============================================================================

bucket         = "terraform-state-us-east-2-production"
key            = "us-east-2/06-observability/production/terraform.tfstate"
region         = "us-east-2"
dynamodb_table = "terraform-locks-us-east-2-production"
encrypt        = true
kms_key_id     = "alias/terraform-state-production"
