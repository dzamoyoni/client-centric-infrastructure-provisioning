# =============================================================================
# Database Layer - Common Configuration
# =============================================================================
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Terraform State
terraform_state_bucket = "ohio-01-terraform-state-production"
terraform_state_region = "us-east-2"

# Database Instance Configuration
key_name              = "ohio-01-key"
master_instance_type  = "t3.medium"
replica_instance_type = "t3.medium"

# Storage Configuration
data_volume_size   = 100
wal_volume_size    = 50
backup_volume_size = 50

# AMI Configuration (Debian 13)
postgres_ami_id = "ami-0b4bbe381ba0dd99b"  # Debian 13 backports us-east-2

# Management Access
management_cidr_blocks = [
  "178.162.141.130/32",
  "165.90.14.138/32",
  "41.72.206.78/32",
  "102.217.4.85/32"
]

# Database Credentials (use AWS Secrets Manager in production)
database_passwords = {
  "est-test-a" = "change-me-in-production"
  "est-test-b" = "change-me-in-production"
}
replication_passwords = {
  "est-test-a" = "change-me-in-production"
  "est-test-b" = "change-me-in-production"
}
