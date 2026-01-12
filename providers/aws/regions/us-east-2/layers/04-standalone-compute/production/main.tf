# =============================================================================
# Standalone Compute Layer - Per-Client Analytics Instances
# =============================================================================
# This layer creates analytics EC2 instances in each client's dedicated VPC
# for maximum isolation and security.
#
# Client-Centric Architecture:
# - Each client's analytics instances in their dedicated VPC
# - Client-specific security groups scoped to client VPC CIDR
# - Complete isolation - no cross-client network access
# - Integrated with per-client VPCs and EKS clusters
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
  
  backend "s3" {
    # Backend configuration loaded from backend.hcl
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

# TAGGING STRATEGY: Provider-level default tags for consistency
# All AWS resources will automatically inherit tags from provider configuration
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      # Core identification
      Project         = "${var.region}-${var.environment}"
      Environment     = var.environment
      Region          = var.region
      
      # Operational
      ManagedBy       = "Terraform"
      Layer           = "04-Standalone-Compute"
      DeploymentPhase = "Layer-4"
      
      # Governance
      CriticalInfra   = "false"
      BackupRequired  = "true"
      SecurityLevel   = "High"
      
      # Cost Management
      CostCenter      = "IT-Infrastructure"
      BillingGroup    = "Platform-Engineering"
      
      # Platform specific
      ClusterRole     = "Primary"
      PlatformType    = "Analytics"
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# DATA SOURCES - Foundation and Platform Layer Outputs
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/01-foundation/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/02-platform/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

# Get subnet details for CIDR information
data "aws_subnet" "client_subnets" {
  for_each = toset(local.all_client_subnet_ids)
  id       = each.value
}

# =============================================================================
# Local Values
# =============================================================================

# LOCALS - Per-Client VPC Configuration
locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs = data.terraform_remote_state.foundation.outputs.client_vpcs
  
  # Platform layer outputs - per-client EKS clusters
  client_clusters = data.terraform_remote_state.platform.outputs.client_clusters
  
  # Filter enabled clients with analytics enabled
  enabled_analytics_clients = {
    for name, config in var.clients : name => config
    if config.enabled && config.compute.analytics_enabled
  }
  
  # Validate all enabled clients have VPCs
  missing_vpcs = [
    for name in keys(local.enabled_analytics_clients) : name
    if !contains(keys(local.client_vpcs), name)
  ]
  
  # Client-specific configurations from clients.auto.tfvars
  client_configs = {
    for name, config in local.enabled_analytics_clients : name => {
      # Client's dedicated VPC
      vpc_id           = local.client_vpcs[name].vpc_id
      vpc_cidr         = local.client_vpcs[name].vpc_cidr
      
      # Compute subnets for analytics instances
      compute_subnet_ids = local.client_vpcs[name].compute_subnet_ids
      
      # EKS subnets CIDRs for security group rules
      eks_subnet_ids = local.client_vpcs[name].eks_subnet_ids
      
      # Compute security group from VPC
      compute_security_group_id = local.client_vpcs[name].compute_security_group_id
      
      # Instance configuration
      instance_type    = config.compute.instance_type
      root_volume_size = config.compute.root_volume_size
      data_volume_size = config.compute.data_volume_size
      
      # Client metadata
      client_code = config.client_code
      tier        = config.tier
    }
  }
  
  # Flatten all subnet IDs for data source
  all_client_subnet_ids = flatten([
    for config in local.client_configs : concat(
      config.compute_subnet_ids,
      config.eks_subnet_ids
    )
  ])
}

# =============================================================================
# Latest Amazon Linux AMI
# =============================================================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# Client-Scoped Security Groups
# =============================================================================

resource "aws_security_group" "client_analytics" {
  for_each = local.client_configs
  
  name_prefix = "${replace(each.key, "-", "_")}-analytics-sg-"
  description = "Security group for ${each.key} analytics instances in dedicated VPC"
  vpc_id      = each.value.vpc_id

  # SSH access only from client's VPC CIDR
  ingress {
    description = "SSH access from ${each.key} VPC only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [each.value.vpc_cidr]
  }

  # Analytics application ports (Jupyter, etc.) - client VPC only
  ingress {
    description = "Analytics application ports from ${each.key} VPC only"
    from_port   = 8888
    to_port     = 8890
    protocol    = "tcp"
    cidr_blocks = [each.value.vpc_cidr]
  }

  # Custom application port - client VPC only
  ingress {
    description = "Custom analytics port from ${each.key} VPC only"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [each.value.vpc_cidr]
  }

  # Database access (to client's own database) - client VPC only
  ingress {
    description = "Database access from ${each.key} VPC only"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [each.value.vpc_cidr]
  }

  # All outbound traffic (for package installation, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name           = "${replace(each.key, "-", "_")}-analytics-sg"
    Client         = each.key
    ClientTier     = var.clients[each.key].tier
    CostCenter     = var.clients[each.key].metadata.cost_center
    BusinessUnit   = var.clients[each.key].metadata.business_unit
    Industry       = var.clients[each.key].metadata.industry
    Purpose        = "analytics-compute"
    NetworkScope   = "client-vpc-only"
    Type           = "security-group"
  }
}

# =============================================================================
# IAM Role for Analytics Instances
# =============================================================================

resource "aws_iam_role" "analytics_instance" {
  for_each = local.client_configs
  
  name = "${replace(each.key, "-", "_")}_analytics_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name         = "${replace(each.key, "-", "_")}_analytics_instance_role"
    Client       = each.key
    ClientTier   = var.clients[each.key].tier
    CostCenter   = var.clients[each.key].metadata.cost_center
    BusinessUnit = var.clients[each.key].metadata.business_unit
    Purpose      = "analytics-compute"
    Type         = "iam-role"
  }
}

resource "aws_iam_instance_profile" "analytics_instance" {
  for_each = local.client_configs
  
  name = "${replace(each.key, "-", "_")}_analytics_instance_profile"
  role = aws_iam_role.analytics_instance[each.key].name

  tags = {
    Name         = "${replace(each.key, "-", "_")}_analytics_instance_profile"
    Client       = each.key
    ClientTier   = var.clients[each.key].tier
    CostCenter   = var.clients[each.key].metadata.cost_center
    BusinessUnit = var.clients[each.key].metadata.business_unit
    Purpose      = "analytics-compute"
    Type         = "instance-profile"
  }
}

# Attach essential managed policies
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  for_each = local.client_configs
  
  role       = aws_iam_role.analytics_instance[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  for_each = local.client_configs
  
  role       = aws_iam_role.analytics_instance[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# =============================================================================
# Analytics EC2 Instance
# =============================================================================

resource "aws_instance" "client_analytics" {
  for_each = local.client_configs
  
  ami                     = data.aws_ami.amazon_linux.id
  instance_type          = each.value.instance_type
  key_name               = "terraform-key-us-east-2"  # Using existing key pair
  subnet_id              = each.value.compute_subnet_ids[0]  # Deploy to first compute subnet
  vpc_security_group_ids = [aws_security_group.client_analytics[each.key].id]
  iam_instance_profile   = aws_iam_instance_profile.analytics_instance[each.key].name

  # Disable public IP assignment
  associate_public_ip_address = false
  
  # Enhanced monitoring
  monitoring = true
  
  # Instance metadata options for security
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  # Root volume configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_size
    encrypted             = true
    delete_on_termination = false
    iops                  = 3000
    throughput            = 125
    
    tags = {
      Name         = "${replace(each.key, "-", "_")}_analytics_root_volume"
      Client       = each.key
      ClientTier   = var.clients[each.key].tier
      CostCenter   = var.clients[each.key].metadata.cost_center
      BusinessUnit = var.clients[each.key].metadata.business_unit
      Purpose      = "analytics-compute"
      VolumeType   = "root"
    }
  }

  # Analytics data volume
  ebs_block_device {
    device_name           = "/dev/xvdf"
    volume_type           = "gp3"
    volume_size           = each.value.data_volume_size
    encrypted             = true
    delete_on_termination = false
    iops                  = 4000
    throughput            = 250

    tags = {
      Name         = "${replace(each.key, "-", "_")}_analytics_data_volume"
      Client       = each.key
      ClientTier   = var.clients[each.key].tier
      CostCenter   = var.clients[each.key].metadata.cost_center
      BusinessUnit = var.clients[each.key].metadata.business_unit
      Purpose      = "analytics-data"
      VolumeType   = "data"
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/analytics-userdata.sh", {
    CLIENT_NAME  = each.key
    REGION       = var.region
    ENVIRONMENT  = var.environment
    VPC_CIDR     = each.value.vpc_cidr
  }))

  tags = {
    Name              = "${replace(each.key, "-", "_")}_analytics_instance"
    Client            = each.key
    ClientTier        = var.clients[each.key].tier
    CostCenter        = var.clients[each.key].metadata.cost_center
    BusinessUnit      = var.clients[each.key].metadata.business_unit
    Industry          = var.clients[each.key].metadata.industry
    Purpose           = "analytics-compute"
    NetworkScope      = "client-vpc-only"
    HighAvailability  = "false"
    MonitoringEnabled = "true"
  }
}

# =============================================================================
# SSM Parameters for Client Discovery
# =============================================================================

resource "aws_ssm_parameter" "analytics_endpoint" {
  for_each = local.client_configs
  
  name  = "/terraform/${var.environment}/${each.key}/analytics/endpoint"
  type  = "String"
  value = aws_instance.client_analytics[each.key].private_ip

  tags = {
    Name         = "${each.key}_analytics_endpoint"
    Client       = each.key
    ClientTier   = var.clients[each.key].tier
    CostCenter   = var.clients[each.key].metadata.cost_center
    BusinessUnit = var.clients[each.key].metadata.business_unit
    Purpose      = "analytics-discovery"
    Type         = "ssm-parameter"
  }
}

resource "aws_ssm_parameter" "analytics_instance_id" {
  for_each = local.client_configs
  
  name  = "/terraform/${var.environment}/${each.key}/analytics/instance-id"
  type  = "String"
  value = aws_instance.client_analytics[each.key].id

  tags = {
    Name         = "${each.key}_analytics_instance_id"
    Client       = each.key
    ClientTier   = var.clients[each.key].tier
    CostCenter   = var.clients[each.key].metadata.cost_center
    BusinessUnit = var.clients[each.key].metadata.business_unit
    Purpose      = "analytics-discovery"
    Type         = "ssm-parameter"
  }
}

# VALIDATION CHECKS
resource "null_resource" "cross_layer_validation" {
  # Ensure foundation layer is compatible
  lifecycle {
    precondition {
      condition     = length(local.missing_vpcs) == 0
      error_message = "Missing VPCs for enabled clients: ${join(", ", local.missing_vpcs)}. Ensure foundation layer created VPCs for all enabled clients."
    }
    
    precondition {
      condition     = length(keys(local.client_configs)) > 0
      error_message = "No client configurations available. Ensure clients are enabled with analytics_enabled=true and have VPCs in foundation layer."
    }
  }
  
  triggers = {
    client_vpcs_version = md5(jsonencode(keys(local.client_vpcs)))
    compute_config_version = md5(jsonencode({
      # project_name removed - using client-centric naming
      environment  = var.environment
      region       = var.region
    }))
  }
}
