# EKS Platform Wrapper Module - Outputs
# Standardized outputs for consistent integration across all infrastructure layers

# =============================================================================
# CLUSTER INFORMATION
# =============================================================================

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_id" {
  description = "The ID/name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks.cluster_version
}

# =============================================================================
# SECURITY
# =============================================================================

output "cluster_primary_security_group_id" {
  description = "Cluster security group created by Amazon EKS"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

# =============================================================================
# NODE GROUPS
# =============================================================================

output "node_groups" {
  description = "Map of EKS managed node groups"
  value = {
    for name, ng in aws_eks_node_group.this : name => {
      arn            = ng.arn
      id             = ng.id
      status         = ng.status
      capacity_type  = ng.capacity_type
      instance_types = ng.instance_types
      scaling_config = ng.scaling_config
    }
  }
}

output "node_group_asg_names" {
  description = "Map of node group key => ASG name, for use in aws_autoscaling_attachment"
  value = {
    for name, ng in aws_eks_node_group.this : name => ng.resources[0].autoscaling_groups[0].name
  }
}

output "node_group_role_arn" {
  description = "IAM role ARN for node groups"
  value       = aws_iam_role.node_group.arn
}

# =============================================================================
# EBS CSI DRIVER
# =============================================================================

output "ebs_csi_irsa_role_arn" {
  description = "IAM role ARN for the EBS CSI driver service account"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

# =============================================================================
# PLATFORM SUMMARY
# =============================================================================

output "platform_summary" {
  description = "Comprehensive summary of the EKS platform deployment"
  value = {
    cluster_name    = module.eks.cluster_name
    cluster_version = module.eks.cluster_version
    cluster_region  = var.region
    environment     = var.environment
    vpc_id          = var.vpc_id

    endpoint_access = {
      public  = var.enable_public_access
      private = true
    }

    addons_enabled = {
      coredns            = true
      vpc_cni            = true
      kube_proxy         = true
      ebs_csi_driver     = true
      pod_identity_agent = true
    }

    node_groups = {
      for name, config in var.node_groups : name => {
        client         = config.client
        instance_types = config.instance_types
        scaling        = "${config.min_size}-${config.max_size}"
        desired        = config.desired_size
        capacity_type  = config.capacity_type
      }
    }
  }
}
