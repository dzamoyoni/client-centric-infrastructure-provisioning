# =============================================================================
# Standalone Compute Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State
terraform_state_bucket = "ohio-01-terraform-state-production"
terraform_state_region = "us-east-2"

# AMI Configuration (Debian 13)
analytics_ami_id = "ami-0b4bbe381ba0dd99b"  # Debian 13 backports us-east-2

# SSH Key
key_name = "ohio-01-key"
