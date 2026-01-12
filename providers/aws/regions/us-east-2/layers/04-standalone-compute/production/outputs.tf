# =============================================================================
# Outputs: Standalone Compute Layer - Analytics Instances
# =============================================================================

# =============================================================================
# Client Analytics Instance Information
# =============================================================================

output "analytics_instances" {
  description = "Information about deployed analytics instances per client"
  value = {
    for client, instance in aws_instance.client_analytics : client => {
      instance_id       = instance.id
      private_ip        = instance.private_ip
      instance_type     = instance.instance_type
      availability_zone = instance.availability_zone
      subnet_id         = instance.subnet_id
      security_group_id = aws_security_group.client_analytics[client].id
      
      # Connection information
      ssh_connection = "ssh -i ohio-01-keypair.pem ec2-user@${instance.private_ip}"
      
      # Volume information
      volumes = {
        root_volume_id = [
          for vol in instance.ebs_block_device :
          vol.volume_id if vol.device_name == "/dev/xvda"
        ]
        data_volume_id = [
          for vol in instance.ebs_block_device :
          vol.volume_id if vol.device_name == "/dev/xvdf"
        ]
      }
    }
  }
}

# =============================================================================
# Security Group Information
# =============================================================================

output "security_groups" {
  description = "Security group information for client analytics instances"
  value = {
    for client, sg in aws_security_group.client_analytics : client => {
      security_group_id   = sg.id
      security_group_name = sg.name
      vpc_id              = sg.vpc_id
      
      # Network access scope
      allowed_cidr_blocks = [local.client_configs[client].vpc_cidr]
      network_scope       = "client-vpc-only"
    }
  }
}

# =============================================================================
# IAM Information
# =============================================================================

output "iam_roles" {
  description = "IAM roles and profiles for analytics instances"
  value = {
    for client, role in aws_iam_role.analytics_instance : client => {
      role_arn             = role.arn
      role_name            = role.name
      instance_profile_arn = aws_iam_instance_profile.analytics_instance[client].arn
      instance_profile_name = aws_iam_instance_profile.analytics_instance[client].name
    }
  }
}

# =============================================================================
# SSM Parameters
# =============================================================================

output "ssm_parameters" {
  description = "SSM parameters for service discovery"
  value = {
    for client in keys(aws_ssm_parameter.analytics_endpoint) : client => {
      endpoint_parameter    = aws_ssm_parameter.analytics_endpoint[client].name
      instance_id_parameter = aws_ssm_parameter.analytics_instance_id[client].name
    }
  }
}

# =============================================================================
# Network Integration Summary
# =============================================================================

output "network_integration" {
  description = "Network integration summary for client analytics instances"
  value = {
    client_vpcs = {
      for client, config in local.client_configs : client => {
        vpc_id             = config.vpc_id
        vpc_cidr           = config.vpc_cidr
        compute_subnet_ids = config.compute_subnet_ids
        network_scope      = "client-vpc-isolated"
        
        # Database access (within same client VPC)
        database_access_allowed = true
        cross_client_access     = false
      }
    }
  }
}

# =============================================================================
# Layer Summary
# =============================================================================

output "compute_layer_summary" {
  description = "Summary of standalone compute layer deployment"
  value = {
    layer_name    = "04-standalone-compute"
    environment   = var.environment
    region        = data.aws_region.current.name
    project       = var.project_name
    
    # Deployment status
    active_clients = keys(local.enabled_analytics_clients)
    total_instances = length(aws_instance.client_analytics)
    
    # Instance configurations
    instance_configs = {
      for client, config in local.enabled_analytics_clients : client => {
        instance_type = config.compute.instance_type
        root_volume = config.compute.root_volume_size
        data_volume = config.compute.data_volume_size
        tier = config.tier
      }
    }
    
    # Security features
    security_features = {
      subnet_isolation     = "enabled"
      encrypted_volumes    = "enabled"
      iam_managed_access   = "enabled"
      cloudwatch_monitoring = "enabled"
      ssm_management       = "enabled"
    }
    
    # Integration status
    integration = {
      foundation_layer = "✅ Connected"
      platform_layer   = "✅ Connected"
      vpc_integration  = "✅ Active"
    }
  }
}

# =============================================================================
# Connection Instructions
# =============================================================================

output "connection_instructions" {
  description = "Instructions for connecting to analytics instances"
  value = {
    for client, instance in aws_instance.client_analytics : client => {
      # Direct SSH (from within VPC)
      ssh_command = "aws ssm start-session --target ${instance.id}"
      
      # Application access URLs (from within client subnets)
      application_urls = {
        jupyter_lab  = "http://${instance.private_ip}:8888"
        custom_app   = "http://${instance.private_ip}:3000"
      }
      
      # Database connection (to client's own database)
      database_connection = "postgresql://[user]:[password]@[database-ip]:5432/[database-name]"
      
      # Network requirements
      network_requirements = {
        access_method   = "VPC internal only"
        vpc_cidr        = local.client_configs[client].vpc_cidr
        isolation_level = "client-vpc-isolated"
      }
    }
  }
}

# =============================================================================
# Monitoring and Management
# =============================================================================

output "monitoring_endpoints" {
  description = "Monitoring and management endpoints"
  value = {
    for client, instance in aws_instance.client_analytics : client => {
      cloudwatch_logs = "/aws/ec2/${instance.id}"
      ssm_session     = "aws ssm start-session --target ${instance.id}"
      
      # CloudWatch dashboard suggestion
      dashboard_metrics = [
        "AWS/EC2/CPUUtilization",
        "AWS/EC2/NetworkIn",
        "AWS/EC2/NetworkOut",
        "AWS/EBS/VolumeReadBytes",
        "AWS/EBS/VolumeWriteBytes"
      ]
    }
  }
}