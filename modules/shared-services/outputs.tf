# Outputs for Shared Services Module

output "cluster_autoscaler_service_account_arn" {
  description = "ARN of the cluster autoscaler service account"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler[0].iam_role_arn : null
}

output "aws_load_balancer_controller_service_account_arn" {
  description = "ARN of the AWS Load Balancer Controller service account"
  value       = var.enable_aws_load_balancer_controller ? module.aws_load_balancer_controller[0].iam_role_arn : null
}

output "external_dns_service_account_arn" {
  description = "ARN of the external DNS service account"
  value       = var.enable_external_dns ? module.external_dns[0].iam_role_arn : null
}
