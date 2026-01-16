# =============================================================================
# Platform Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State
terraform_state_bucket = "ohio-01-terraform-state-production"
terraform_state_region = "us-east-2"

# EKS Configuration
cluster_version = "1.31"

# Management Access
enable_public_access = true
management_cidr_blocks = [
  "178.162.141.130/32",
  "165.90.14.138/32",
  "41.72.206.78/32",
  "102.217.4.85/32"
]
