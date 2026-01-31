# ============================================================================
# Layer 01.5: Transit Gateway - Backend Configuration
# ============================================================================
# State Management: Centralized S3 backend with DynamoDB locking
# Created by: Layer 00-Bootstrap
# ============================================================================

terraform {
  backend "s3" {
    # Backend configuration loaded from:
    # 1. ../../../../../../../backend-config.tfvars (centralized config)
    # 2. backend.hcl (layer-specific key)
    #
    # Usage:
    # terraform init -backend-config=../../../../../../../backend-config.tfvars \
    #                -backend-config=backend.hcl
  }
}
