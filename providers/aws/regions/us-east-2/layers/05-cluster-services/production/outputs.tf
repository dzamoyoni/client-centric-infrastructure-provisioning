# Cluster Services Layer Outputs - Per-Client Architecture
# Exposes per-client essential cluster services information

#  CLUSTER AUTOSCALER OUTPUTS
output "cluster_autoscaler_enabled" {
  description = "Whether cluster autoscaler is enabled"
  value       = var.enable_cluster_autoscaler
}

output "cluster_autoscaler_version" {
  description = "Version of cluster autoscaler deployed"
  value       = var.cluster_autoscaler_version
}

output "cluster_autoscaler_service_account_arns" {
  description = "ARNs of the cluster autoscaler service accounts per client"
  value = var.enable_cluster_autoscaler ? {
    for client, service in module.client_cluster_services :
    client => service.cluster_autoscaler_service_account_arn
  } : {}
}

# AWS LOAD BALANCER CONTROLLER OUTPUTS
output "aws_load_balancer_controller_enabled" {
  description = "Whether AWS Load Balancer Controller is enabled"
  value       = var.enable_aws_load_balancer_controller
}

output "aws_load_balancer_controller_version" {
  description = "Version of AWS Load Balancer Controller deployed"
  value       = var.aws_load_balancer_controller_version
}

output "aws_load_balancer_controller_service_account_arns" {
  description = "ARNs of the AWS Load Balancer Controller service accounts per client"
  value = var.enable_aws_load_balancer_controller ? {
    for client, service in module.client_cluster_services :
    client => service.aws_load_balancer_controller_service_account_arn
  } : {}
}

#  METRICS SERVER OUTPUTS
output "metrics_server_enabled" {
  description = "Whether metrics server is enabled"
  value       = var.enable_metrics_server
}

output "metrics_server_version" {
  description = "Version of metrics server deployed"
  value       = var.metrics_server_version
}

#  EXTERNAL DNS OUTPUTS
output "external_dns_enabled" {
  description = "Whether external DNS is enabled"
  value       = var.enable_external_dns
}

output "external_dns_service_account_arns" {
  description = "ARNs of the external DNS service accounts per client"
  value = var.enable_external_dns ? {
    for client, service in module.client_cluster_services :
    client => service.external_dns_service_account_arn
  } : {}
}

#  PER-CLIENT CLUSTER SERVICES SUMMARY
output "client_cluster_services" {
  description = "Summary of deployed essential cluster services per client"
  value = {
    for client, config in local.enabled_clients : client => {
      cluster_name = local.client_clusters[client].cluster_name
      vpc_id       = local.client_vpcs[client].vpc_id
      
      services_deployed = {
        cluster_autoscaler           = var.enable_cluster_autoscaler
        aws_load_balancer_controller = var.enable_aws_load_balancer_controller
        metrics_server               = var.enable_metrics_server
        external_dns                 = var.enable_external_dns
        istio_service_mesh           = var.enable_istio_service_mesh
      }
      
      client_metadata = {
        tier         = config.tier
        client_code  = config.client_code
        cost_center  = config.metadata.cost_center
        business_unit = config.metadata.business_unit
      }
    }
  }
}

#  DEPLOYMENT INSTRUCTIONS
output "deployment_instructions" {
  description = "Per-client deployment verification instructions"
  value = {
    message = "Layer 5: Per-Client Cluster Services deployed to each client's dedicated cluster"
    verification_per_client = [
      "Update kubeconfig: aws eks update-kubeconfig --name <client-cluster-name> --region ${var.region}",
      "Verify all services: kubectl get pods -A",
      "Test cluster autoscaler: Check ASG scaling with workload deployment",
      "Verify metrics server: kubectl top nodes",
      "Check ALB controller: kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
    ]
    architecture = "Each client has isolated essential cluster services in their dedicated EKS cluster"
  }
}

# =============================================================================
# ARCHITECTURE SUMMARY
# =============================================================================

output "architecture_summary" {
  description = "Summary of per-client architecture"
  value = {
    architecture_type = "Per-Client Complete Isolation"
    
    isolation_strategy = {
      method            = "Dedicated VPC + Dedicated EKS Cluster per Client"
      network_isolation = "Complete - no cross-client network access"
      compute_isolation = "Complete - dedicated nodes per client"
      data_isolation    = "Complete - dedicated databases per client"
    }
    
    per_client_resources = {
      vpc                  = "Dedicated VPC with unique CIDR"
      eks_cluster          = "Dedicated EKS cluster"
      node_groups          = "Single node group for all workloads (applications + cluster services)"
      cluster_services     = "Cluster Autoscaler, ALB Controller, Metrics Server, ExternalDNS, Istio"
      observability        = "Prometheus, Grafana, Loki, Tempo (per client)"
      databases            = "Dedicated RDS instances"
      analytics_compute    = "Dedicated EC2 instances"
    }
    
    benefits = [
      "Complete client isolation - zero shared resources",
      "Simplified security and compliance per client",
      "Independent scaling and performance per client",
      "Clear cost allocation per client",
      "No noisy neighbor issues",
      "Easier troubleshooting and maintenance"
    ]
  }
}
