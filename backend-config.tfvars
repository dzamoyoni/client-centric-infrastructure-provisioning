# ============================================================================
# Centralized Backend Configuration
# ============================================================================
# Purpose: Single source of truth for Terraform backend configuration
# Usage: terraform init -backend-config=../../../../../../backend-config.tfvars \
#                        -backend-config=backend-layer.tfvars
#
# This file is version-controlled and shared across all layers
# ============================================================================

# S3 Backend Configuration (created by Layer 00-Bootstrap)
# bucket         = "terraform-state-us-east-2-production"
# region         = "us-east-2"
# dynamodb_table = "terraform-locks-us-east-2-production"
# encrypt        = true

# Note: The 'key' parameter is layer-specific and defined in each layer's backend-layer.tfvars
