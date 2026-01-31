# ============================================================================
# Layer 01.5: Transit Gateway - Configuration
# ============================================================================

# Core Configuration
environment  = "production"
region       = "us-east-2"
contact_email = "dennis.juma00@gmail.com"

# Transit Gateway Configuration
transit_gateway_asn                     = 64512
enable_transit_gateway_flow_logs        = true
transit_gateway_flow_log_retention_days = 7
