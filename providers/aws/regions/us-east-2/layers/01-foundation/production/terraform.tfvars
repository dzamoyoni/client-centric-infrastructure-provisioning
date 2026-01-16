# =============================================================================
# Foundation Layer - Common Configuration
# =============================================================================
# This file contains common/shared configuration values
# Client-specific configurations are in clients.auto.tfvars

# Core Configuration
environment  = "production"
region       = "us-east-2"

# Monitoring (optional)
sns_topic_arn = null
