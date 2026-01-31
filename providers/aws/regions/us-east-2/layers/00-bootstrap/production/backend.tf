# ============================================================================
# Backend Configuration - Layer 00 Bootstrap
# ============================================================================
# Bootstrap layer uses LOCAL backend (not S3)
#
# Why? Chicken-and-egg problem:
#   - This layer CREATES the S3 bucket for Terraform state
#   - It cannot use that S3 bucket for its own state (doesn't exist yet)
#
# Bootstrap state is stored locally in: terraform.tfstate
# 
# IMPORTANT: 
#   - Commit terraform.tfstate to Git (or store securely)
#   - OR: Use a pre-created, manually-managed S3 bucket for bootstrap state
#   - This file uses local backend for simplicity and independence
# ============================================================================

# No backend configuration = local backend
# Terraform will store state in ./terraform.tfstate

# Alternative: If you want to use a manually-created S3 bucket for bootstrap state:
# terraform {
#   backend "s3" {
#     bucket         = "manually-created-bootstrap-state-bucket"
#     key            = "bootstrap/terraform.tfstate"
#     region         = "us-east-2"
#     dynamodb_table = "manually-created-bootstrap-locks"
#     encrypt        = true
#   }
# }
