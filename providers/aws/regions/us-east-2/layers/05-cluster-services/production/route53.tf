# =============================================================================
# Route53 Hosted Zones - Per-Client DNS Management
# =============================================================================
# Each client gets a dedicated hosted zone for their subdomain under ezra.world
# Example: client-a.ezra.world, client-b.ezra.world
#
# This eliminates the hybrid approach - everything is managed by Terraform

# Data source for parent zone (ezra.world)
data "aws_route53_zone" "parent" {
  count        = var.enable_external_dns ? 1 : 0
  name         = var.parent_dns_zone
  private_zone = false
}

# Create hosted zone for each client
resource "aws_route53_zone" "client_zones" {
  for_each = var.enable_external_dns ? local.enabled_clients : {}
  
  name    = "${each.key}.${var.parent_dns_zone}"
  comment = "Hosted zone for ${each.key} (${each.value.metadata.full_name}) - Managed by Terraform"
  
  tags = merge(
    local.standard_tags,
    {
      Name         = "${each.key}.${var.parent_dns_zone}"
      Client       = each.key
      ClientTier   = each.value.tier
      ClientCode   = each.value.client_code
      Domain       = "${each.key}.${var.parent_dns_zone}"
      CostCenter   = each.value.metadata.cost_center
      BusinessUnit = each.value.metadata.business_unit
    }
  )
}

# Create NS records in parent zone to delegate to client zones
resource "aws_route53_record" "client_ns_delegation" {
  for_each = var.enable_external_dns ? local.enabled_clients : {}
  
  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = "${each.key}.${var.parent_dns_zone}"
  type    = "NS"
  ttl     = 300
  
  records = aws_route53_zone.client_zones[each.key].name_servers
}

# Optional: Create A record for client's main domain pointing to their ingress
# This will be a placeholder - ExternalDNS will manage actual records
resource "aws_route53_record" "client_root_placeholder" {
  for_each = var.enable_external_dns && var.create_root_placeholder ? local.enabled_clients : {}
  
  zone_id = aws_route53_zone.client_zones[each.key].zone_id
  name    = "${each.key}.${var.parent_dns_zone}"
  type    = "TXT"
  ttl     = 300
  
  records = [
    "Managed by Terraform - ExternalDNS will create actual records",
    "Client: ${each.value.metadata.full_name}",
    "Tier: ${each.value.tier}"
  ]
}

# Locals to build zone ID map for ExternalDNS configuration
locals {
  # Map of client names to their zone IDs
  client_zone_ids = {
    for client, zone in aws_route53_zone.client_zones : client => zone.zone_id
  }
  
  # List of all zone IDs (for backward compatibility)
  all_zone_ids = values(aws_route53_zone.client_zones)[*].zone_id
}
