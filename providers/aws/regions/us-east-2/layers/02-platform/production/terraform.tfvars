# =============================================================================
# Platform Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State (for reading Foundation layer remote state)
terraform_state_bucket = "terraform-state-us-east-2-production-myorg"
terraform_state_region = "us-east-2"

# EKS Configuration
cluster_version = "1.35"

# Management Access
enable_public_access = true
management_cidr_blocks = [
  "41.72.206.78/32",
  "102.217.4.85/32",
  "102.68.79.205/32"
]
