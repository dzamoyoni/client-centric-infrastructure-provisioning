# ============================================================================
# ROUTE53 DNS RECORDS - SMART SEAMLESS ALB INTEGRATION
# ============================================================================
# Automatically discovers Route53 zones by domain name (no zone IDs needed!)
# 
# How it works:
#   1. Layer 02 first run: ALB created, DNS skipped (zones don't exist yet)
#   2. Layer 05 deployment: Creates Route53 zones (client-a.xyz, client-b.xyz)
#   3. Layer 02 re-run: Automatically discovers zones and creates DNS records
#
# Configuration in /clients.auto.tfvars:
#   dns = {
#     enabled = true
#     domain_name = "client-a.xyz"  # Layer 05 creates this zone
#     public_subdomain = "app"
#     internal_subdomain = "internal"
#     create_route53_records = true
#   }
# ============================================================================

# ============================================================================
# Data Sources - Check Zone Existence Before Lookup
# ============================================================================
# Use external data source to check if zones exist (won't fail if missing)
# This allows Layer 02 to run before Layer 05 creates the zones

data "external" "check_zone_exists" {
  for_each = {
    for name, config in local.enabled_alb_clients : name => config
    if try(config.dns.enabled, false) &&
       try(config.dns.create_route53_records, false) &&
       try(config.dns.domain_name, "") != ""
  }

  program = ["bash", "-c", <<-EOF
    ZONE_ID=$(aws route53 list-hosted-zones-by-name \
      --dns-name "${each.value.dns.domain_name}" \
      --max-items 1 \
      --query "HostedZones[?Name=='${each.value.dns.domain_name}.'].Id | [0]" \
      --output text 2>/dev/null || echo "")
    
    if [[ "$ZONE_ID" != "None" && "$ZONE_ID" != "" && "$ZONE_ID" != "null" ]]; then
      # Extract just the zone ID (remove /hostedzone/ prefix)
      ZONE_ID=$(echo "$ZONE_ID" | sed 's|/hostedzone/||')
      echo "{\"exists\": \"true\", \"zone_id\": \"$ZONE_ID\"}"
    else
      echo "{\"exists\": \"false\", \"zone_id\": \"\"}"
    fi
  EOF
  ]
}

# Only lookup zones that are confirmed to exist
data "aws_route53_zone" "client_zones" {
  for_each = {
    for name, result in data.external.check_zone_exists : name => local.enabled_alb_clients[name]
    if result.result.exists == "true"
  }

  name         = each.value.dns.domain_name
  private_zone = false
}

# Check private zone existence
data "external" "check_private_zone_exists" {
  for_each = {
    for name, config in local.enabled_alb_clients : name => config
    if try(config.dns.enabled, false) &&
       try(config.dns.create_route53_records, false) &&
       try(config.dns.private_zone_domain_name, "") != "" &&
       config.dns.private_zone_domain_name != null
  }

  program = ["bash", "-c", <<-EOF
    ZONE_ID=$(aws route53 list-hosted-zones-by-name \
      --dns-name "${each.value.dns.private_zone_domain_name}" \
      --max-items 1 \
      --query "HostedZones[?Name=='${each.value.dns.private_zone_domain_name}.' && Config.PrivateZone==\`true\`].Id | [0]" \
      --output text 2>/dev/null || echo "")
    
    if [[ "$ZONE_ID" != "None" && "$ZONE_ID" != "" && "$ZONE_ID" != "null" ]]; then
      ZONE_ID=$(echo "$ZONE_ID" | sed 's|/hostedzone/||')
      echo "{\"exists\": \"true\", \"zone_id\": \"$ZONE_ID\"}"
    else
      echo "{\"exists\": \"false\", \"zone_id\": \"\"}"
    fi
  EOF
  ]
}

# Only lookup private zones that exist
data "aws_route53_zone" "client_private_zones" {
  for_each = {
    for name, result in data.external.check_private_zone_exists : name => local.enabled_alb_clients[name]
    if result.result.exists == "true"
  }

  name         = each.value.dns.private_zone_domain_name
  private_zone = true
}

# ============================================================================
# Locals - Zone Discovery Status
# ============================================================================

locals {
  # Track which zones were successfully discovered using external check results
  discovered_zones = {
    for name, config in local.enabled_alb_clients : name => {
      # Use the external check results (won't fail if zone doesn't exist)
      public_zone_discovered = try(
        data.external.check_zone_exists[name].result.exists == "true",
        false
      )
      private_zone_discovered = try(
        data.external.check_private_zone_exists[name].result.exists == "true",
        false
      )

      # Get zone IDs from the actual data source (only populated if zone exists)
      public_zone_id  = try(data.aws_route53_zone.client_zones[name].zone_id, "")
      private_zone_id = try(data.aws_route53_zone.client_private_zones[name].zone_id, "")

      # Fallback: Use public zone for internal records if no private zone
      internal_zone_id = try(
        data.aws_route53_zone.client_private_zones[name].zone_id,
        data.aws_route53_zone.client_zones[name].zone_id,
        ""
      )
    }
    if try(config.dns.enabled, false) && try(config.dns.create_route53_records, false)
  }

  # Clients ready for DNS record creation (zone exists)
  clients_ready_for_dns = {
    for name, config in local.enabled_alb_clients : name => config
    if try(config.dns.enabled, false) &&
       try(config.dns.create_route53_records, false) &&
       try(local.discovered_zones[name].public_zone_discovered, false)
  }

  # Clients waiting for Layer 05 (zones not found)
  clients_waiting_for_zones = [
    for name, config in local.enabled_alb_clients : name
    if try(config.dns.enabled, false) &&
       try(config.dns.create_route53_records, false) &&
       !try(local.discovered_zones[name].public_zone_discovered, false)
  ]
}

# ============================================================================
# PUBLIC ALB DNS RECORDS (Internet-Facing)
# ============================================================================
# Creates: app.client-a.xyz → Public ALB
# Only created if zone exists AND client has internet-facing/both ALB

resource "aws_route53_record" "public_alb" {
  for_each = {
    for name, config in local.clients_ready_for_dns : name => config
    if contains(["internet-facing", "both"], config.alb.type) &&
       try(module.client_alb[name].public_alb_dns_name, null) != null
  }
  
  zone_id = local.discovered_zones[each.key].public_zone_id
  name    = "${each.value.dns.public_subdomain}.${each.value.dns.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.client_alb[each.key].public_alb_dns_name
    zone_id                = module.client_alb[each.key].public_alb_zone_id
    evaluate_target_health = try(each.value.dns.evaluate_target_health, true)
  }
  
  depends_on = [module.client_alb]
}

# ============================================================================
# INTERNAL ALB DNS RECORDS (Private)
# ============================================================================
# Creates: internal.client-a.xyz → Internal ALB
# Uses private zone if exists, otherwise public zone

resource "aws_route53_record" "internal_alb" {
  for_each = {
    for name, config in local.clients_ready_for_dns : name => config
    if contains(["internal", "both"], config.alb.type) &&
       try(module.client_alb[name].internal_alb_dns_name, null) != null &&
       local.discovered_zones[name].internal_zone_id != ""
  }
  
  zone_id = local.discovered_zones[each.key].internal_zone_id
  name    = "${each.value.dns.internal_subdomain}.${each.value.dns.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.client_alb[each.key].internal_alb_dns_name
    zone_id                = module.client_alb[each.key].internal_alb_zone_id
    evaluate_target_health = try(each.value.dns.evaluate_target_health, true)
  }
  
  depends_on = [module.client_alb]
}

# ============================================================================
# WILDCARD DNS RECORDS (Optional)
# ============================================================================
# Creates: *.client-a.xyz → Public ALB
# Only if explicitly enabled

resource "aws_route53_record" "public_alb_wildcard" {
  for_each = {
    for name, config in local.clients_ready_for_dns : name => config
    if try(config.dns.create_wildcard_record, false) &&
       contains(["internet-facing", "both"], config.alb.type) &&
       try(module.client_alb[name].public_alb_dns_name, null) != null
  }
  
  zone_id = local.discovered_zones[each.key].public_zone_id
  name    = "*.${each.value.dns.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.client_alb[each.key].public_alb_dns_name
    zone_id                = module.client_alb[each.key].public_alb_zone_id
    evaluate_target_health = try(each.value.dns.evaluate_target_health, true)
  }
  
  depends_on = [module.client_alb]
}

# ============================================================================
# OUTPUTS - DNS Information
# ============================================================================

output "dns_zone_discovery_status" {
  description = "Status of Route53 zone discovery for each client"
  value = {
    for name, status in local.discovered_zones : name => {
      public_zone_found  = status.public_zone_discovered
      private_zone_found = status.private_zone_discovered
      public_zone_id     = status.public_zone_id
      private_zone_id    = status.private_zone_id
      status_message = status.public_zone_discovered ? "Zone discovered - DNS records created" : "Zone not found - Deploy Layer 05 first"
    }
    if contains(keys(local.enabled_alb_clients), name) &&
       try(local.enabled_alb_clients[name].dns.enabled, false)
  }
}

output "dns_records" {
  description = "DNS records created for client ALBs"
  value = {
    public = {
      for name, record in aws_route53_record.public_alb : name => {
        fqdn        = record.fqdn
        alb_dns     = module.client_alb[name].public_alb_dns_name
        zone_id     = record.zone_id
        record_type = record.type
      }
    }
    internal = {
      for name, record in aws_route53_record.internal_alb : name => {
        fqdn        = record.fqdn
        alb_dns     = module.client_alb[name].internal_alb_dns_name
        zone_id     = record.zone_id
        record_type = record.type
      }
    }
  }
}

output "client_endpoints" {
  description = "Client application endpoints (URLs)"
  value = {
    for name, config in local.enabled_alb_clients : name => {
      # Show URLs if DNS records were created
      public_url = (
        try(config.dns.enabled, false) && 
        contains(["internet-facing", "both"], config.alb.type) &&
        local.discovered_zones[name].public_zone_discovered
      ) ? "https://${config.dns.public_subdomain}.${config.dns.domain_name}:${config.alb.https_external_port}" : null
      
      internal_url = (
        try(config.dns.enabled, false) && 
        contains(["internal", "both"], config.alb.type) &&
        local.discovered_zones[name].internal_zone_id != ""
      ) ? "https://${config.dns.internal_subdomain}.${config.dns.domain_name}:${config.alb.https_external_port}" : null
      
      # Always show ALB DNS names
      alb_public_dns   = try(module.client_alb[name].public_alb_dns_name, null)
      alb_internal_dns = try(module.client_alb[name].internal_alb_dns_name, null)
      
      # Status
      dns_status = try(config.dns.enabled, false) ? (local.discovered_zones[name].public_zone_discovered ? "DNS records active" : "Waiting for Route53 zone (deploy Layer 05)") : "DNS disabled"
    }
  }
}

output "clients_waiting_for_dns" {
  description = "Clients that need Layer 05 deployed before DNS records can be created"
  value = length(local.clients_waiting_for_zones) > 0 ? {
    count   = length(local.clients_waiting_for_zones)
    clients = local.clients_waiting_for_zones
    action  = "Deploy Layer 05 (Cluster Services) to create Route53 zones, then re-run Layer 02"
  } : null
}
