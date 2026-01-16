# EKS Platform Wrapper Module
# Wraps terraform-aws-modules/eks/aws with defined standards and conventions
# This ensures consistency across all EKS deployments in all regions/environments

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

#  LOCALS - Enterprise Standards
locals {
  # Standard tags applied to all resources
  standard_tags = {
    Project         = var.project_name
    Environment     = var.environment
    ManagedBy       = "Terraform"
    CriticalInfra   = "true"
    BackupRequired  = "true"
    SecurityLevel   = "High"
    Region          = var.region
    Layer           = "Platform"
    DeploymentPhase = "Phase-2"
    Architecture    = "Client-Centric"
  }

  # Standard cluster naming 
  cluster_name = var.cluster_name != null ? var.cluster_name : var.project_name

  # User data for node bootstrap with log rotation configuration
  # This prevents disk space exhaustion from container logs on lean nodes
  node_userdata = <<-EOT
    #!/bin/bash
    set -e
    
    # Configure kubelet log rotation to prevent disk space issues
    # Especially critical for lean nodes with limited disk (20-50GB)
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    cat <<'EOF' > /etc/systemd/system/kubelet.service.d/10-log-rotation.conf
    [Service]
    Environment="KUBELET_EXTRA_ARGS=--container-log-max-size=${var.container_log_max_size} --container-log-max-files=${var.container_log_max_files}"
    EOF
    
    # Configure containerd log rotation
    mkdir -p /etc/containerd
    
    # Ensure containerd config includes log rotation settings
    if [ ! -f /etc/containerd/config.toml ]; then
      containerd config default > /etc/containerd/config.toml
    fi
    
    # Add log rotation to containerd CRI plugin if not already present
    if ! grep -q "max_container_log_line_size" /etc/containerd/config.toml; then
      sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd\]/a \
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]\n\
          SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null || true
    fi
    
    # Set up logrotate for container logs as additional safety
    cat <<'EOF' > /etc/logrotate.d/containers
    /var/log/pods/*/*/*.log {
        rotate ${var.container_log_max_files}
        size ${replace(var.container_log_max_size, "Mi", "M")}
        missingok
        notifempty
        compress
        delaycompress
        copytruncate
    }
    /var/log/containers/*.log {
        rotate ${var.container_log_max_files}
        size ${replace(var.container_log_max_size, "Mi", "M")}
        missingok
        notifempty
        compress
        delaycompress
        copytruncate
    }
    EOF
    
    # Reload systemd daemon
    systemctl daemon-reload
  EOT

  # Standard node group configuration
  standard_node_group_defaults = {
    capacity_type              = "ON_DEMAND"
    max_unavailable_percentage = 25
    disk_type                  = "gp3"

    # Security standards
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 2
      instance_metadata_tags      = "enabled"
    }

    # Monitoring standards
    monitoring = {
      enabled = true
    }

    # Standard labels for all nodes
    labels = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      # Company can be set via common_tags
      Architecture = "Client-Centric"
    }
  }
}

# EKS CLUSTER - Official Module with Enterprise Standards
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  # Standard cluster configuration
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # VPC Configuration from foundation layer
  vpc_id     = var.vpc_id
  subnet_ids = var.platform_subnet_ids

  # Security standards
  cluster_endpoint_public_access       = var.enable_public_access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.management_cidr_blocks

  # Encryption standards
  enable_irsa = true

  # Logging standards
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Standard addons with proper IRSA configuration
  cluster_addons = {
    coredns                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent                 = true
      service_account_role_arn    = module.ebs_csi_irsa_role.iam_role_arn
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  # Node Groups with custom launch template for log rotation
  eks_managed_node_groups = {
    for name, config in var.node_groups : name => merge(
      local.standard_node_group_defaults,
      config,
      {
        # Apply naming standards
        name = "${local.cluster_name}-${config.name_suffix}"

        # Custom IAM role name without trailing hyphen
        iam_role_name = "${local.cluster_name}-${config.name_suffix}-nodes"

        # Enable custom user data for log rotation configuration
        enable_bootstrap_user_data = true
        pre_bootstrap_user_data    = local.node_userdata

        # Add taints if specified
        taints = lookup(config, "taints", null) != null ? {
          for taint_name, taint_config in config.taints : taint_name => {
            key    = taint_config.key
            value  = taint_config.value
            effect = taint_config.effect
          }
        } : {}

        # Merge standard labels with custom labels
        labels = merge(
          local.standard_node_group_defaults.labels,
          lookup(config, "labels", {}),
          {
            NodeGroup = name
            Client    = lookup(config, "client", "platform")
          }
        )

        # Apply standard tags
        tags = merge(
          local.standard_tags,
          lookup(config, "tags", {}),
          {
            Name      = "${local.cluster_name}-${config.name_suffix}-nodes"
            Purpose   = lookup(config, "purpose", "Client-Centric Node Group")
            Client    = lookup(config, "client", "platform")
            NodeGroup = name
          }
        )
      }
    )
  }

  # Access configuration
  access_entries = var.access_entries

  # Standard cluster tags
  tags = merge(local.standard_tags, var.additional_tags)
}

# DATA SOURCE - Current AWS account for access patterns
data "aws_caller_identity" "current" {}

# EBS CSI DRIVER IRSA ROLE - Required for proper EBS CSI functionality
# This creates an IAM role that the EBS CSI driver can assume via IRSA
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.cluster_name}-ebs-csi-"
  role_description = "IRSA role for EBS CSI driver in ${local.cluster_name} cluster"

  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = merge(local.standard_tags, {
    Name = "${local.cluster_name}-ebs-csi-irsa"
    Purpose = "EBS CSI Driver Service Account Role"
  })
}
