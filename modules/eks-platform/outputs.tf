# EKS Cluster Wrapper Module - Outputs
# Standardized outputs for consistent integration across all infrastructure layers

# CLUSTER INFORMATION
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

output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = module.eks.cluster_security_group_id
}

output "cluster_service_cidr" {
  description = "The CIDR block where Kubernetes pod and service IP addresses are assigned from"
  value       = module.eks.cluster_service_cidr
}

output "cluster_status" {
  description = "Status of the EKS cluster (CREATING, ACTIVE, DELETING, FAILED)"
  value       = module.eks.cluster_status
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks.cluster_version
}

#  SECURITY AND ACCESS
output "cluster_tls_certificate_sha1_fingerprint" {
  description = "The SHA1 fingerprint of the public key of the cluster's certificate"
  value       = module.eks.cluster_tls_certificate_sha1_fingerprint
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "IAM role ARN for the EBS CSI driver service account"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

# NODE GROUPS
output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "eks_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by EKS managed node groups"
  value       = module.eks.eks_managed_node_groups_autoscaling_group_names
}

output "node_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the node shared security group"
  value       = module.eks.node_security_group_arn
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

# PLATFORM SUMMARY
output "platform_summary" {
  description = "Comprehensive summary of the EKS platform deployment"
  value = {
    # Cluster information
    cluster_name    = module.eks.cluster_name
    cluster_version = module.eks.cluster_version
    cluster_region  = var.region
    environment     = var.environment

    # Network configuration
    vpc_id           = var.vpc_id
    platform_subnets = length(var.platform_subnet_ids)

    # Security configuration  
    endpoint_access = {
      public  = var.enable_public_access
      private = true
    }

    # Features enabled
    addons_enabled = {
      coredns            = true
      vpc_cni            = true
      kube_proxy         = true
      ebs_csi_driver     = true
      pod_identity_agent = true
    }

    logging_enabled = true
    irsa_enabled    = true

    # Node groups summary
    node_groups_enabled = {
      for name, config in var.node_groups : name => {
        client         = config.client
        instance_types = config.instance_types
        capacity       = "${config.min_size}-${config.max_size}"
        desired        = config.desired_size
      }
    }

    # Infrastructure standards applied
    infrastructure_standards = {
      naming_convention  = "applied"
      tagging_standards  = "applied"
      security_hardening = "applied"
      monitoring_enabled = "applied"
      backup_configured  = "applied"
    }
  }
}

# SECURITY NOTICE
output "security_notice" {
  description = "Important security information for the EKS cluster"
  value = {
    message = "EKS Cluster deployed with security best practices"
    actions_required = [
      "Configure kubectl access using: aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}",
      "Verify node groups are healthy: kubectl get nodes",
      "Review security groups and NACLs for compliance",
      "Configure additional monitoring and alerting as needed"
    ]
    documentation = "https://docs.aws.amazon.com/eks/latest/userguide/"
  }
}
