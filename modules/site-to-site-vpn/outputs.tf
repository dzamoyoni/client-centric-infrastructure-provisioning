# Outputs for Site-to-Site VPN Module

# Customer Gateway Information
output "customer_gateway_id" {
  description = "ID of the customer gateway"
  value       = var.enabled ? aws_customer_gateway.main[0].id : null
}

output "customer_gateway_bgp_asn" {
  description = "BGP ASN of the customer gateway"
  value       = var.enabled ? aws_customer_gateway.main[0].bgp_asn : null
}

output "customer_gateway_ip_address" {
  description = "IP address of the customer gateway"
  value       = var.enabled ? aws_customer_gateway.main[0].ip_address : null
}

# VPN Gateway Information
output "vpn_gateway_id" {
  description = "ID of the VPN gateway"
  value       = var.enabled ? aws_vpn_gateway.main[0].id : null
}

output "vpn_gateway_amazon_side_asn" {
  description = "Amazon side BGP ASN of the VPN gateway"
  value       = var.enabled ? aws_vpn_gateway.main[0].amazon_side_asn : null
}

# VPN Connection Information
output "vpn_connection_id" {
  description = "ID of the VPN connection"
  value       = var.enabled ? aws_vpn_connection.main[0].id : null
}

output "vpn_connection_customer_gateway_configuration" {
  description = "Customer gateway configuration for the VPN connection"
  value       = var.enabled ? aws_vpn_connection.main[0].customer_gateway_configuration : null
  sensitive   = true
}

# Tunnel Information
output "tunnel1_address" {
  description = "Public IP address of VPN tunnel 1"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel1_address : null
}

output "tunnel1_cgw_inside_address" {
  description = "Customer gateway inside IP address for tunnel 1"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel1_cgw_inside_address : null
}

output "tunnel1_vgw_inside_address" {
  description = "Virtual gateway inside IP address for tunnel 1"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel1_vgw_inside_address : null
}

output "tunnel2_address" {
  description = "Public IP address of VPN tunnel 2"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel2_address : null
}

output "tunnel2_cgw_inside_address" {
  description = "Customer gateway inside IP address for tunnel 2"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel2_cgw_inside_address : null
}

output "tunnel2_vgw_inside_address" {
  description = "Virtual gateway inside IP address for tunnel 2"
  value       = var.enabled ? aws_vpn_connection.main[0].tunnel2_vgw_inside_address : null
}

# Configuration Summary
output "vpn_summary" {
  description = "Summary of VPN infrastructure created"
  value = var.enabled ? {
    client_name         = var.client_name
    vpc_id              = var.vpc_id
    customer_gateway_id = aws_customer_gateway.main[0].id
    vpn_gateway_id      = aws_vpn_gateway.main[0].id
    vpn_connection_id   = aws_vpn_connection.main[0].id
    tunnel1_address     = aws_vpn_connection.main[0].tunnel1_address
    tunnel2_address     = aws_vpn_connection.main[0].tunnel2_address
    static_routes_only  = var.static_routes_only
    onprem_cidr_blocks  = var.onprem_cidr_blocks
    bgp_asn             = var.bgp_asn
    amazon_side_asn     = var.amazon_side_asn
    vpn_logging_enabled = var.enable_vpn_logging
  } : null
}

# VPN Configuration Note
output "vpn_configuration_note" {
  description = "Note about VPN configuration"
  value       = var.enabled ? "Download VPN configuration from AWS Console after deployment" : null
}
