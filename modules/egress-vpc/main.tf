# ============================================================================
# Egress VPC Module - Centralized NAT Gateway
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

locals {
  sanitized_project_name = replace(lower(var.project_name), " ", "-")

  # Build return route map dynamically if transit_gateway_id is present
  spoke_return_routes = var.transit_gateway_id == null ? {} : {
    for cidr in distinct(var.spoke_vpcs_cidrs) :
    replace(cidr, "/", "_") => cidr
  }
}

# ============================================================================
# VPC & Gateway Infrastructure
# ============================================================================

resource "aws_vpc" "egress" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name    = "egress-vpc-${var.region}"
    Purpose = "Centralized Internet Egress for Multi-VPC Architecture"
    Layer   = "Foundation"
    VPCType = "Egress"
  })
}

resource "aws_internet_gateway" "egress" {
  vpc_id = aws_vpc.egress.id

  tags = merge(var.common_tags, {
    Name    = "egress-igw-${var.region}"
    Purpose = "Internet Gateway for Egress VPC"
    Layer   = "Foundation"
  })
}

# ============================================================================
# Subnets
# ============================================================================

resource "aws_subnet" "public" {
  count = var.enable_high_availability ? length(var.availability_zones) : 1

  vpc_id                  = aws_vpc.egress.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name       = "egress-public-${var.availability_zones[count.index]}"
    Purpose    = "Public Subnet for NAT Gateway"
    Layer      = "Foundation"
    AZ         = var.availability_zones[count.index]
    SubnetType = "Public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.egress.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name       = "egress-private-${var.availability_zones[count.index]}"
    Purpose    = "Private Subnet for Transit Gateway Attachment"
    Layer      = "Foundation"
    AZ         = var.availability_zones[count.index]
    SubnetType = "Private"
  })
}

# ============================================================================
# NAT Gateways
# ============================================================================

resource "aws_eip" "nat" {
  count = var.enable_high_availability ? length(var.availability_zones) : 1

  domain = "vpc"

  tags = merge(var.common_tags, {
    Name    = "egress-nat-eip-${var.availability_zones[count.index]}"
    Purpose = "Elastic IP for Centralized NAT Gateway"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.egress]
}

resource "aws_nat_gateway" "egress" {
  count = var.enable_high_availability ? length(var.availability_zones) : 1

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name    = "egress-nat-${var.availability_zones[count.index]}"
    Purpose = "Centralized NAT Gateway for Multi-VPC Egress"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.egress]
}

# ============================================================================
# Public Route Table & Dynamic Return Routing
# ============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.egress.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.egress.id
  }

  tags = merge(var.common_tags, {
    Name    = "egress-public-rt"
    Purpose = "Public Route Table for Egress VPC"
    Layer   = "Foundation"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# DYNAMIC RETURN ROUTES BACK TO TGW
resource "aws_route" "public_to_spoke_tgw" {
  for_each = local.spoke_return_routes

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = each.value
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_route_table.public]

  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# ============================================================================
# Private Route Tables
# ============================================================================

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.egress.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.enable_high_availability ? aws_nat_gateway.egress[count.index].id : aws_nat_gateway.egress[0].id
  }

  tags = merge(var.common_tags, {
    Name    = "egress-private-rt-${var.availability_zones[count.index]}"
    Purpose = "Private Route Table to NAT Gateway"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ============================================================================
# VPC Endpoints
# ============================================================================

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.egress.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(var.common_tags, {
    Name    = "egress-s3-endpoint"
    Purpose = "S3 VPC Endpoint for Cost Optimization"
    Layer   = "Foundation"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.egress.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(var.common_tags, {
    Name    = "egress-dynamodb-endpoint"
    Purpose = "DynamoDB VPC Endpoint for Cost Optimization"
    Layer   = "Foundation"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name_prefix = "egress-vpc-endpoints-"
  vpc_id      = aws_vpc.egress.id
  description = "Security group for Egress VPC endpoints"

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = "egress-vpc-endpoints-sg"
    Purpose = "VPC Endpoints Security Group"
    Layer   = "Foundation"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Flow Logs
# ============================================================================

locals {
  dynamic_flow_log_role_name = coalesce(
    var.flow_log_role_name,
    "${local.sanitized_project_name}-egress-vpc-flow-log-role-${var.region}"
  )

  flow_log_role_arn = !var.enable_flow_logs ? null : (
    var.create_flow_log_role ? aws_iam_role.flow_log[0].arn : data.aws_iam_role.existing_flow_log[0].arn
  )

  flow_log_role_id = !var.enable_flow_logs ? null : (
    var.create_flow_log_role ? aws_iam_role.flow_log[0].id : data.aws_iam_role.existing_flow_log[0].id
  )
}

resource "aws_flow_log" "egress" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = local.flow_log_role_arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.egress.id

  tags = merge(var.common_tags, {
    Name    = "egress-vpc-flow-logs"
    Purpose = "VPC Traffic Flow Logging"
    Layer   = "Foundation"
  })
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${local.sanitized_project_name}-egress-${var.region}"
  retention_in_days = var.flow_log_retention_days
  skip_destroy      = true

  tags = merge(var.common_tags, {
    Name    = "egress-vpc-flow-logs"
    Purpose = "VPC Flow Logs Storage"
    Layer   = "Foundation"
  })
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs && var.create_flow_log_role ? 1 : 0

  name = local.dynamic_flow_log_role_name

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
    Name    = "egress-vpc-flow-log-role"
    Purpose = "VPC Flow Logs IAM Role"
    Layer   = "Foundation"
  })
}

data "aws_iam_role" "existing_flow_log" {
  count = var.enable_flow_logs && !var.create_flow_log_role ? 1 : 0

  name = local.dynamic_flow_log_role_name
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs && var.create_flow_log_role ? 1 : 0

  name = "${local.sanitized_project_name}-egress-vpc-flow-log-policy"
  role = local.flow_log_role_id

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