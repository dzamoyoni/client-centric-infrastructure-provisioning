# ============================================================================
# Platform Layer Outputs - Per-Client EKS Clusters
# ============================================================================
# Each client has a dedicated EKS cluster in their own VPC
# Other layers access client-specific clusters via:
#   data.terraform_remote_state.platform.outputs.client_clusters["client-name"]
# ============================================================================

# ============================================================================
# Per-Client EKS Cluster Details - Primary Output
# ============================================================================
# Access pattern: outputs.client_clusters["client-name"].cluster_endpoint

output "client_clusters" {
  description = "Complete EKS cluster details per client - use this for cross-layer lookups"
  value = {
    for name, cluster in module.client_eks_clusters : name => {
      # Cluster identification
      cluster_id      = cluster.cluster_id
      cluster_name    = cluster.cluster_name
      cluster_arn     = cluster.cluster_arn
      cluster_version = cluster.cluster_version
      
      # Connection details (for other layers)
      cluster_endpoint                   = cluster.cluster_endpoint
      cluster_certificate_authority_data = cluster.cluster_certificate_authority_data
      cluster_oidc_issuer_url            = cluster.cluster_oidc_issuer_url
      oidc_provider_arn                  = cluster.oidc_provider_arn
      
      # Security groups (for integrations)
      cluster_security_group_id = cluster.cluster_security_group_id
      node_security_group_id    = cluster.node_security_group_id
      
      # Node groups
      eks_managed_node_groups = cluster.eks_managed_node_groups
      
      # Client metadata
      client_code = var.clients[name].client_code
      tier        = var.clients[name].tier
    }
  }
  sensitive = true  # Contains sensitive cluster data
}

# ============================================================================
# Platform Summary
# ============================================================================

output "platform_summary" {
  description = "Summary of per-client EKS clusters deployed"
  value = {
    region      = var.region
    environment = var.environment
    
    # Per-client cluster counts
    total_clusters       = length(module.client_eks_clusters)
    provisioned_clusters = keys(module.client_eks_clusters)
    
    # Per-client cluster details
    client_clusters = {
      for name, cluster in module.client_eks_clusters : name => {
        cluster_name    = cluster.cluster_name
        cluster_version = cluster.cluster_version
        node_groups     = length(cluster.eks_managed_node_groups)
        client_code     = var.clients[name].client_code
        tier            = var.clients[name].tier
      }
    }
    
    architecture = "per-client-eks-clusters"
  }
}

# ============================================================================
# Deployment Notice
# ============================================================================

output "deployment_notice" {
  description = "Per-Client EKS Clusters deployment summary and next steps"
  value       = <<-EOT
    ╔═══════════════════════════════════════════════════════════════════╗
    ║  PHASE 2: PLATFORM LAYER - PER-CLIENT EKS CLUSTERS              ║
    ╚═══════════════════════════════════════════════════════════════════╝
    
    SUCCESSFULLY DEPLOYED:
    - Dedicated EKS cluster per client
    - Complete Kubernetes isolation
    - Client-specific node groups
    - OIDC providers for IRSA
    - Security groups per cluster
    
    EKS CLUSTERS SUMMARY:
    - Total Clusters: ${length(module.client_eks_clusters)}
    - Kubernetes Version: ${var.cluster_version}
    - Provisioned Clusters: ${join(", ", keys(module.client_eks_clusters))}
    
    CLUSTER DETAILS:
    ${join("\n    ", [for name, cluster in module.client_eks_clusters : "  • ${name}: ${cluster.cluster_name}"])}
    
    KUBECONFIG ACCESS:
    ${join("\n    ", [for name, cluster in module.client_eks_clusters : "  aws eks update-kubeconfig --name ${cluster.cluster_name} --region ${var.region}"])}
    
    ➡️  NEXT PHASE: Layer 03 - Database
    - Access clusters via: outputs.client_clusters["client-name"].cluster_endpoint
    - Each client's database will be in their dedicated VPC
    - Complete data isolation between clients
    
    COST ESTIMATE: ~$73/month per cluster (control plane) + nodes
  EOT
}
