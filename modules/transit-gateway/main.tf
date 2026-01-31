# ============================================================================
# Transit Gateway Module - Regional Network Hub
# ============================================================================
# Provides centralized routing between VPCs and on-premises networks
# Supports: VPC attachments, route tables, cross-account sharing, VPN
# Use Case: Centralized egress, inter-VPC communication, hybrid connectivity
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# Transit Gateway
# ============================================================================

resource "aws_ec2_transit_gateway" "main" {
  description                     = var.description
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = var.default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.default_route_table_propagation ? "enable" : "disable"
  dns_support                     = var.dns_support ? "enable" : "disable"
  vpn_ecmp_support                = var.vpn_ecmp_support ? "enable" : "disable"
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments ? "enable" : "disable"

  tags = merge(var.common_tags, {
    Name    = var.name
    Purpose = "Regional Network Hub for Multi-VPC Architecture"
  })
}

# ============================================================================
# VPC Attachments
# ============================================================================

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  dns_support                                     = try(each.value.dns_support, true) ? "enable" : "disable"
  ipv6_support                                    = try(each.value.ipv6_support, false) ? "enable" : "disable"
  appliance_mode_support                          = try(each.value.appliance_mode_support, false) ? "enable" : "disable"
  transit_gateway_default_route_table_association = try(each.value.transit_gateway_default_route_table_association, true)
  transit_gateway_default_route_table_propagation = try(each.value.transit_gateway_default_route_table_propagation, true)

  tags = merge(
    var.common_tags,
    try(each.value.tags, {}),
    {
      Name   = "${var.name}-${each.key}-attachment"
      VPC    = each.key
      Purpose = "Transit Gateway VPC Attachment"
    }
  )

  # Wait for TGW to be available
  depends_on = [aws_ec2_transit_gateway.main]
}

# ============================================================================
# Transit Gateway Route Tables
# ============================================================================

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = var.route_tables

  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(
    var.common_tags,
    try(each.value.tags, {}),
    {
      Name    = "${var.name}-${each.key}-rt"
      Purpose = try(each.value.description, "Transit Gateway Route Table")
    }
  )

  depends_on = [aws_ec2_transit_gateway.main]
}

# ============================================================================
# Route Table Associations
# ============================================================================

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.route_table_associations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.vpc_attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_key].id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table.this
  ]
}

# ============================================================================
# Route Table Propagations
# ============================================================================

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.route_table_propagations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.vpc_attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_key].id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table.this
  ]
}

# ============================================================================
# Static Routes
# ============================================================================

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.static_routes

  destination_cidr_block         = each.value.destination_cidr_block
  transit_gateway_attachment_id  = try(each.value.vpc_attachment_key, null) != null ? aws_ec2_transit_gateway_vpc_attachment.this[each.value.vpc_attachment_key].id : null
  blackhole                      = try(each.value.blackhole, false)
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_key].id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table.this
  ]
}

# ============================================================================
# Cross-Account Sharing (RAM)
# ============================================================================

resource "aws_ram_resource_share" "tgw" {
  count = var.enable_cross_account_sharing ? 1 : 0

  name                      = "${var.name}-share"
  allow_external_principals = var.allow_external_principals

  tags = merge(var.common_tags, {
    Name    = "${var.name}-ram-share"
    Purpose = "Transit Gateway Cross-Account Sharing"
  })
}

resource "aws_ram_resource_association" "tgw" {
  count = var.enable_cross_account_sharing ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ram_principal_association" "tgw" {
  for_each = var.enable_cross_account_sharing ? toset(var.shared_account_ids) : []

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

# ============================================================================
# CloudWatch Flow Logs (Optional)
# ============================================================================

resource "aws_cloudwatch_log_group" "tgw_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/transit-gateway/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.common_tags, {
    Name    = "${var.name}-flow-logs"
    Purpose = "Transit Gateway Flow Logs"
  })
}

# IAM Role for Flow Logs
resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.name}-flow-log-role"
    Purpose = "Transit Gateway Flow Logs IAM Role"
  })
}

# IAM Policy for Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-flow-log-policy"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "tgw" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn              = aws_iam_role.flow_log[0].arn
  log_destination           = aws_cloudwatch_log_group.tgw_flow_logs[0].arn
  log_destination_type      = "cloud-watch-logs"
  traffic_type              = "ALL"
  transit_gateway_id        = aws_ec2_transit_gateway.main.id
  max_aggregation_interval  = 60  # Transit Gateway only supports 60 seconds

  tags = merge(var.common_tags, {
    Name    = "${var.name}-flow-logs"
    Purpose = "Transit Gateway Traffic Monitoring"
  })
}
