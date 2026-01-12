# =============================================================================
# Backend Configuration Template - us-east-2 region
# =============================================================================
# This template provides the standard backend configuration for all layers
# in the us-east-2 region. Use this as a reference when creating new layers.
# =============================================================================

# Standard backend configuration for us-east-2
bucket         = "ohio-01-terraform-state-production"
region         = "us-east-2"
encrypt        = true
dynamodb_table = "terraform-locks-us-east-2"

# Layer-specific key format:
# key = "providers/aws/regions/us-east-2/layers/{LAYER_NAME}/{ENVIRONMENT}/terraform.tfstate"
# 
# Examples:
# - Foundation:         "providers/aws/regions/us-east-2/layers/01-foundation/production/terraform.tfstate"
# - Platform:           "providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfstate"
# - Databases:          "providers/aws/regions/us-east-2/layers/03-databases/production/terraform.tfstate"
# - Standalone Compute: "providers/aws/regions/us-east-2/layers/03-standalone-compute/production/terraform.tfstate"
# - Observability:      "providers/aws/regions/us-east-2/layers/03.5-observability/production/terraform.tfstate"
# - Database Layer:     "providers/aws/regions/us-east-2/layers/03-database-layer/production/terraform.tfstate"
# - Client Nodegroups:  "providers/aws/regions/us-east-2/layers/05-client-nodegroups/production/terraform.tfstate"
# - Shared Services:    "providers/aws/regions/us-east-2/layers/06-shared-services/production/terraform.tfstate"

# =============================================================================
# Usage Instructions:
# 1. Copy this template to each layer directory as backend.hcl
# 2. Update the key parameter with the appropriate layer name
# 3. Initialize with: terraform init -backend-config=backend.hcl
# =============================================================================