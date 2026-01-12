# Client Subnet Isolation Module
# Creates isolated subnets per client with dedicated networking

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# STANDALONE COMPUTE SUBNETS - Per Client
resource "aws_subnet" "compute" {
  count = var.enabled ? length(var.availability_zones) : 0

  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.client_cidr_block, 4, count.index) # /26 subnets (62 IPs each)
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

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# DATABASE SUBNETS - Per Client
resource "aws_subnet" "database" {
  count = var.enabled ? length(var.availability_zones) : 0

  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.client_cidr_block, 4, count.index + 2) # /26 subnets (62 IPs each)
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

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# EKS NODEGROUP SUBNETS - Per Client (Largest allocation)
resource "aws_subnet" "eks" {
  count = var.enabled ? length(var.availability_zones) : 0

  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.client_cidr_block, 2, count.index + 1) # /24 subnets (254 IPs each)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name                                        = "${var.project_name}-${var.client_name}-eks-${var.availability_zones[count.index]}"
    Purpose                                     = "EKS NodeGroup"
    Layer                                       = "EKS"
    Client                                      = var.client_name
    AZ                                          = var.availability_zones[count.index]
    SubnetType                                  = "Private"
    SubnetTier                                  = "EKS"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# CLIENT ROUTE TABLES - Isolated per Client and AZ
resource "aws_route_table" "client" {
  count = var.enabled ? length(var.availability_zones) : 0

  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway_ids[count.index]
  }

  # Optional on-premises routes via VPN
  dynamic "route" {
    for_each = var.onprem_cidr_blocks
    content {
      cidr_block = route.value
      gateway_id = var.vpn_gateway_id
    }
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-rt-${var.availability_zones[count.index]}"
    Purpose = "Client Isolated Route Table"
    Layer   = "Foundation"
    Client  = var.client_name
    AZ      = var.availability_zones[count.index]
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# ROUTE TABLE ASSOCIATIONS - Compute Subnets
resource "aws_route_table_association" "compute" {
  count = var.enabled ? length(aws_subnet.compute) : 0

  subnet_id      = aws_subnet.compute[count.index].id
  route_table_id = aws_route_table.client[count.index].id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# ROUTE TABLE ASSOCIATIONS - Database Subnets
resource "aws_route_table_association" "database" {
  count = var.enabled ? length(aws_subnet.database) : 0

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.client[count.index].id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# ROUTE TABLE ASSOCIATIONS - EKS Subnets
resource "aws_route_table_association" "eks" {
  count = var.enabled ? length(aws_subnet.eks) : 0

  subnet_id      = aws_subnet.eks[count.index].id
  route_table_id = aws_route_table.client[count.index].id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

# CLIENT-SPECIFIC SECURITY GROUPS

# Compute Layer Security Group
resource "aws_security_group" "compute" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-${var.client_name}-compute-"
  vpc_id      = var.vpc_id
  description = "Security group for ${var.client_name} compute instances"

  # SSH access from VPN
  ingress {
    description = "SSH from management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_cidr_blocks
  }

  # HTTP/HTTPS for application traffic
  ingress {
    description = "HTTP from EKS subnets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = aws_subnet.eks[*].cidr_block
  }

  ingress {
    description = "HTTPS from EKS subnets"
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
    Purpose = "Compute Layer Security"
    Layer   = "Compute"
    Client  = var.client_name
  })

  # lifecycle {
  #   prevent_destroy = true
  #   create_before_destroy = true
  # }
}

# Database Layer Security Group - For PostgreSQL on EC2
resource "aws_security_group" "database" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-${var.client_name}-database-"
  vpc_id      = var.vpc_id
  description = "Security group for ${var.client_name} PostgreSQL database instances on EC2"

  # Custom PostgreSQL ports from compute subnets
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} from compute subnets"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.compute[*].cidr_block
    }
  }

  # Custom PostgreSQL ports from EKS subnets
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} from EKS subnets"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.eks[*].cidr_block
    }
  }

  # Custom PostgreSQL ports from other database subnets (for replication)
  dynamic "ingress" {
    for_each = var.database_ports
    content {
      description = "PostgreSQL port ${ingress.value} from database subnets"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = aws_subnet.database[*].cidr_block
    }
  }

  # SSH for maintenance (restricted to management networks)
  ingress {
    description = "SSH from management networks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_cidr_blocks
  }

  # PostgreSQL monitoring ports (e.g., pg_stat_statements, pgAdmin)
  ingress {
    description = "PostgreSQL monitoring from management"
    from_port   = 5050
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = var.management_cidr_blocks
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
    Purpose = "PostgreSQL Database on EC2 Security"
    Layer   = "Database"
    Client  = var.client_name
  })

  # lifecycle {
  #   prevent_destroy = true
  #   create_before_destroy = true
  # }
}

# EKS NodeGroup Security Group
resource "aws_security_group" "eks" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-${var.client_name}-eks-"
  vpc_id      = var.vpc_id
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
    description = "NodePort from EKS subnets"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = aws_subnet.eks[*].cidr_block
  }

  # SSH access for troubleshooting
  ingress {
    description = "SSH from management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_cidr_blocks
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
    Layer   = "EKS"
    Client  = var.client_name
  })

  # lifecycle {
  #   prevent_destroy = true
  #   create_before_destroy = true
  # }
}

#  NETWORK ACCESS CONTROL LISTS - Additional Security Layer
resource "aws_network_acl" "client" {
  count = var.enabled ? 1 : 0

  vpc_id = var.vpc_id
  subnet_ids = concat(
    aws_subnet.compute[*].id,
    aws_subnet.database[*].id,
    aws_subnet.eks[*].id
  )

  # Allow inbound traffic within client CIDR
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.client_cidr_block
    from_port  = 0
    to_port    = 0
  }

  # Allow inbound traffic from management networks
  dynamic "ingress" {
    for_each = { for idx, cidr in var.management_cidr_blocks : idx => cidr }
    content {
      protocol   = "-1"
      rule_no    = 200 + ingress.key
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 0
      to_port    = 0
    }
  }

  # Allow return traffic from internet (ephemeral ports)
  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.client_name}-nacl"
    Purpose = "Client Network ACL"
    Layer   = "Foundation"
    Client  = var.client_name
  })

  # lifecycle {
  #   prevent_destroy = true
  # }
}

