# ============================================================================
# Transit Gateway Module - Outputs
# ============================================================================

output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.arn
}

output "transit_gateway_owner_id" {
  description = "Owner ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.owner_id
}

output "transit_gateway_association_default_route_table_id" {
  description = "ID of the default association route table"
  value       = aws_ec2_transit_gateway.main.association_default_route_table_id
}

output "transit_gateway_propagation_default_route_table_id" {
  description = "ID of the default propagation route table"
  value       = aws_ec2_transit_gateway.main.propagation_default_route_table_id
}

# ============================================================================
# VPC Attachments
# ============================================================================

output "vpc_attachment_ids" {
  description = "Map of VPC attachment IDs"
  value = {
    for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id
  }
}

output "vpc_attachments" {
  description = "Map of VPC attachment details"
  value = {
    for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => {
      id                 = v.id
      vpc_id             = v.vpc_id
      subnet_ids         = v.subnet_ids
      vpc_owner_id       = v.vpc_owner_id
      transit_gateway_id = v.transit_gateway_id
    }
  }
}

# ============================================================================
# Route Tables
# ============================================================================

output "route_table_ids" {
  description = "Map of Transit Gateway route table IDs"
  value = {
    for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id
  }
}

output "route_tables" {
  description = "Map of Transit Gateway route table details"
  value = {
    for k, v in aws_ec2_transit_gateway_route_table.this : k => {
      id                                = v.id
      arn                               = v.arn
      default_association_route_table   = v.default_association_route_table
      default_propagation_route_table   = v.default_propagation_route_table
      transit_gateway_id                = v.transit_gateway_id
    }
  }
}

# ============================================================================
# Cross-Account Sharing
# ============================================================================

output "ram_resource_share_id" {
  description = "ID of the RAM resource share (if enabled)"
  value       = try(aws_ram_resource_share.tgw[0].id, null)
}

output "ram_resource_share_arn" {
  description = "ARN of the RAM resource share (if enabled)"
  value       = try(aws_ram_resource_share.tgw[0].arn, null)
}

# ============================================================================
# Flow Logs
# ============================================================================

output "flow_log_id" {
  description = "ID of the Transit Gateway flow log (if enabled)"
  value       = try(aws_flow_log.tgw[0].id, null)
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group for flow logs (if enabled)"
  value       = try(aws_cloudwatch_log_group.tgw_flow_logs[0].name, null)
}

output "flow_log_group_arn" {
  description = "ARN of the CloudWatch log group for flow logs (if enabled)"
  value       = try(aws_cloudwatch_log_group.tgw_flow_logs[0].arn, null)
}
