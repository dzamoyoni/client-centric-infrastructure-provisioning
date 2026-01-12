# VPC Foundation Module - Security-First Design
# Provides secure VPC infrastructure with dual NAT gateways for HA

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# MAIN VPC - High Availability Design
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-vpc-${var.region}"
    Purpose     = "Multi-Client EKS Infrastructure"
    Layer       = "Foundation"
    CIDR        = var.vpc_cidr
    Environment = var.environment
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

#  INTERNET GATEWAY
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-igw-${var.region}"
    Purpose = "Internet Gateway for Public Subnets"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# PUBLIC SUBNETS - For NAT Gateways and Load Balancers
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                     = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Purpose                  = "Public Subnet for NAT Gateways"
    Layer                    = "Foundation"
    AZ                       = var.availability_zones[count.index]
    SubnetType               = "Public"
    "kubernetes.io/role/elb" = "1" # For ELB placement
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

#  ELASTIC IPS for NAT Gateways
resource "aws_eip" "nat" {
  count = length(var.availability_zones)

  domain = "vpc"

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-nat-eip-${var.availability_zones[count.index]}"
    Purpose = "Elastic IP for NAT Gateway"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.main]

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# NAT GATEWAYS - Dual for High Availability
resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-nat-${var.availability_zones[count.index]}"
    Purpose = "NAT Gateway for Private Subnet Internet Access"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.main]

  # lifecycle {
  #   prevent_destroy = true
  # }
}

#  PUBLIC ROUTE TABLE
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-public-rt"
    Purpose = "Public Route Table"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# PUBLIC ROUTE TABLE ASSOCIATIONS
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# PLATFORM SUBNETS - For EKS Control Plane & Shared Services
resource "aws_subnet" "platform" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 6, count.index + 1) # /22 subnets (1,022 IPs each)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name                              = "${var.project_name}-platform-${var.availability_zones[count.index]}"
    Purpose                           = "Platform Services (EKS Control Plane)"
    Layer                             = "Foundation"
    AZ                                = var.availability_zones[count.index]
    SubnetType                        = "Private"
    "kubernetes.io/role/internal-elb" = "1" # For internal ELB placement
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

#  PLATFORM ROUTE TABLES - AZ-specific for HA
resource "aws_route_table" "platform" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-platform-rt-${var.availability_zones[count.index]}"
    Purpose = "Platform Route Table"
    Layer   = "Foundation"
    AZ      = var.availability_zones[count.index]
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# PLATFORM ROUTE TABLE ASSOCIATIONS
resource "aws_route_table_association" "platform" {
  count = length(aws_subnet.platform)

  subnet_id      = aws_subnet.platform[count.index].id
  route_table_id = aws_route_table.platform[count.index].id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# VPC FLOW LOGS - Security & Monitoring
resource "aws_flow_log" "vpc" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-vpc-flow-logs"
    Purpose = "VPC Traffic Flow Logging"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# CLOUDWATCH LOG GROUP for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/flowlogs/${var.project_name}-${var.region}"
  retention_in_days = var.flow_log_retention_days
  
  # Skip destroy if outside of Terraform (prevents conflicts)
  skip_destroy = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-vpc-flow-logs"
    Purpose = "VPC Flow Logs Storage"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   # Prevent accidental deletion
  #   prevent_destroy = true
  # }
}

# IAM ROLE for VPC Flow Logs
resource "aws_iam_role" "flow_log" {
  name = "${var.project_name}-vpc-flow-log-role-${var.region}"

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
    Name    = "${var.project_name}-vpc-flow-log-role"
    Purpose = "VPC Flow Logs IAM Role"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# IAM POLICY for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  name = "${var.project_name}-vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id

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

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# VPC ENDPOINTS - Cost Optimization
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.platform[*].id
  )

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-s3-endpoint"
    Purpose = "S3 VPC Endpoint for Cost Optimization"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.platform[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-ecr-dkr-endpoint"
    Purpose = "ECR Docker VPC Endpoint"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.platform[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-ecr-api-endpoint"
    Purpose = "ECR API VPC Endpoint"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# SECURITY GROUP for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpc-endpoints-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPC endpoints"

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
    Name    = "${var.project_name}-vpc-endpoints-sg"
    Purpose = "VPC Endpoints Security Group"
    Layer   = "Foundation"
  })

  # lifecycle {
  #   prevent_destroy = true
  #   create_before_destroy = true
  # }
}
