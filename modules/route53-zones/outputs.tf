output "hosted_zone_ids" {
  description = "Map of hosted zone names to their zone IDs"
  value       = { for name, zone in aws_route53_zone.zones : name => zone.zone_id }
}

output "hosted_zone_arns" {
  description = "Map of hosted zone names to their ARNs"
  value       = { for name, zone in aws_route53_zone.zones : name => zone.arn }
}

output "hosted_zone_name_servers" {
  description = "Map of hosted zone names to their name servers"
  value       = { for name, zone in aws_route53_zone.zones : name => zone.name_servers }
}

output "zone_arns_list" {
  description = "List of all hosted zone ARNs (for ExternalDNS IRSA)"
  value       = [for zone in aws_route53_zone.zones : zone.arn]
}

output "zone_ids_list" {
  description = "List of all hosted zone IDs (for ExternalDNS zone filtering)"
  value       = [for zone in aws_route53_zone.zones : zone.zone_id]
}
