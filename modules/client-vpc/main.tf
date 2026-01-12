# ============================================================================
# Client VPC Module - Per-Client VPC Isolation
# ============================================================================
# Creates a complete VPC infrastructure for a single client with:
# - Dedicated VPC with client-specific CIDR
# - Public subnets for NAT gateways and load balancers
# - Private subnets for EKS, database, and compute workloads
# - High availability across multiple AZs
# - Security groups for each tier
# - VPC endpoints for cost optimization
# - VPC Flow Logs for security monitoring
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
# VPC - Client-Dedicated Network
# ============================================================================

resource "aws_vpc" "client" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-${var.client_name}-vpc-${var.region}"
    Purpose     = "Dedicated VPC for ${var.client_name}"
    Layer       = "Foundation"
    Client      = var.client_name
    CIDR        = var.vpc_cidr
    Environment = var.environment
  })
}

# ============================================================================
# Internet Gateway
# ============================================================================

resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-igw-${var.region}"
    Purpose = "Internet Gateway for ${var.client_name}"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# ============================================================================
# Public Subnets - For NAT Gateways and Load Balancers
# ============================================================================

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.client.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                     = "${var.project_name}-${var.client_name}-public-${var.availability_zones[count.index]}"
    Purpose                  = "Public Subnet for NAT Gateways and Load Balancers"
    Layer                    = "Foundation"
    Client                   = var.client_name
    AZ                       = var.availability_zones[count.index]
    SubnetType               = "Public"
    "kubernetes.io/role/elb" = "1" # For public ELB placement
  })
}

# ============================================================================
# Elastic IPs for NAT Gateways
# ============================================================================

resource "aws_eip" "nat" {
  count = length(var.availability_zones)

  domain = "vpc"

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-nat-eip-${var.availability_zones[count.index]}"
    Purpose = "Elastic IP for NAT Gateway"
    Layer   = "Foundation"
    Client  = var.client_name
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.client]
}

# ============================================================================
# NAT Gateways - High Availability (One per AZ)
# ============================================================================

resource "aws_nat_gateway" "client" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-nat-${var.availability_zones[count.index]}"
    Purpose = "NAT Gateway for Private Subnet Internet Access"
    Layer   = "Foundation"
    Client  = var.client_name
    AZ      = var.availability_zones[count.index]
  })

  depends_on = [aws_internet_gateway.client]
}

# ============================================================================
# Public Route Table
# ============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.client.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client.id
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-public-rt"
    Purpose = "Public Route Table"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================================
# EKS Subnets - Private (Largest allocation for node groups)
# ============================================================================

resource "aws_subnet" "eks" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.client.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 1) # /20 subnets
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name                                        = "${var.project_name}-${var.client_name}-eks-${var.availability_zones[count.index]}"
    Purpose                                     = "EKS NodeGroup Subnet"
    Layer                                       = "Platform"
    Client                                      = var.client_name
    AZ                                          = var.availability_zones[count.index]
    SubnetType                                  = "Private"
    SubnetTier                                  = "EKS"
    "kubernetes.io/role/internal-elb"           = "1" # For internal ELB placement
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# ============================================================================
# Database Subnets - Private
# ============================================================================

resource "aws_subnet" "database" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.client.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 16) # /24 subnets
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name       = "${var.project_name}-${var.client_name}-database-${var.availability_zones[count.index]}"
    Purpose    = "Database Layer"
    Layer      = "Database"
    Client     = var.client_name
    AZ         = var.availability_zones[count.index]
    SubnetType = "Private"
    SubnetTier = "Database"
  })
}

# ============================================================================
# Compute Subnets - Private (For standalone EC2 instances)
# ============================================================================

resource "aws_subnet" "compute" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.client.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 32) # /24 subnets
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name       = "${var.project_name}-${var.client_name}-compute-${var.availability_zones[count.index]}"
    Purpose    = "Standalone Compute Instances"
    Layer      = "Compute"
    Client     = var.client_name
    AZ         = var.availability_zones[count.index]
    SubnetType = "Private"
    SubnetTier = "Compute"
  })
}

# ============================================================================
# Private Route Tables - AZ-specific for High Availability
# ============================================================================

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.client.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.client[count.index].id
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-private-rt-${var.availability_zones[count.index]}"
    Purpose = "Private Route Table"
    Layer   = "Foundation"
    Client  = var.client_name
    AZ      = var.availability_zones[count.index]
  })
}

# EKS Subnet Route Table Associations
resource "aws_route_table_association" "eks" {
  count = length(aws_subnet.eks)

  subnet_id      = aws_subnet.eks[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database Subnet Route Table Associations
resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Compute Subnet Route Table Associations
resource "aws_route_table_association" "compute" {
  count = length(aws_subnet.compute)

  subnet_id      = aws_subnet.compute[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ============================================================================
# Security Groups
# ============================================================================

# EKS NodeGroup Security Group
resource "aws_security_group" "eks" {
  name_prefix = "${var.project_name}-${var.client_name}-eks-"
  vpc_id      = aws_vpc.client.id
  description = "Security group for ${var.client_name} EKS node groups"

  # Allow all traffic between EKS nodes
  ingress {
    description = "All traffic from EKS nodes"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # NodePort services
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = aws_subnet.eks[*].cidr_block
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-eks-sg"
    Purpose = "EKS NodeGroup Security"
    Layer   = "Platform"
    Client  = var.client_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Database Security Group
resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-${var.client_name}-database-"
  vpc_id      = aws_vpc.client.id
  description = "Security group for ${var.client_name} database instances"

  # PostgreSQL from EKS subnets
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} from EKS"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.eks[*].cidr_block
    }
  }

  # PostgreSQL from compute subnets
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} from compute"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.compute[*].cidr_block
    }
  }

  # PostgreSQL from database subnets (for replication)
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} for replication"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.database[*].cidr_block
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-database-sg"
    Purpose = "Database Security"
    Layer   = "Database"
    Client  = var.client_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Compute Security Group
resource "aws_security_group" "compute" {
  name_prefix = "${var.project_name}-${var.client_name}-compute-"
  vpc_id      = aws_vpc.client.id
  description = "Security group for ${var.client_name} compute instances"

  # HTTP/HTTPS from EKS subnets
  ingress {
    description = "HTTP from EKS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = aws_subnet.eks[*].cidr_block
  }

  ingress {
    description = "HTTPS from EKS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = aws_subnet.eks[*].cidr_block
  }

  # Custom application ports
  dynamic "ingress" {
    for_each = var.custom_ports
    content {
      description = "Custom port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.eks[*].cidr_block
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-compute-sg"
    Purpose = "Compute Security"
    Layer   = "Compute"
    Client  = var.client_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-${var.client_name}-vpc-endpoints-"
  vpc_id      = aws_vpc.client.id
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
    Name    = "${var.project_name}-${var.client_name}-vpc-endpoints-sg"
    Purpose = "VPC Endpoints Security"
    Layer   = "Foundation"
    Client  = var.client_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# VPC Endpoints - Cost Optimization
# ============================================================================

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.client.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-s3-endpoint"
    Purpose = "S3 VPC Endpoint for Cost Optimization"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# ECR Docker Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.client.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.eks[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-ecr-dkr-endpoint"
    Purpose = "ECR Docker VPC Endpoint"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.client.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.eks[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-ecr-api-endpoint"
    Purpose = "ECR API VPC Endpoint"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# ============================================================================
# VPC Flow Logs - Security & Monitoring
# ============================================================================

resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.client.id

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-vpc-flow-logs"
    Purpose = "VPC Traffic Flow Logging"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.project_name}-${var.client_name}-${var.region}"
  retention_in_days = var.flow_log_retention_days
  skip_destroy      = true

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-vpc-flow-logs"
    Purpose = "VPC Flow Logs Storage"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.client_name}-vpc-flow-log-role-${var.region}"

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
    Name    = "${var.project_name}-${var.client_name}-vpc-flow-log-role"
    Purpose = "VPC Flow Logs IAM Role"
    Layer   = "Foundation"
    Client  = var.client_name
  })
}

# IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.client_name}-vpc-flow-log-policy"
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
