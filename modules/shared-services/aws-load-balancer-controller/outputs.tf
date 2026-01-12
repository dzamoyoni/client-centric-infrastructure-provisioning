# Outputs for AWS Load Balancer Controller

output "iam_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role"
  value       = var.external_irsa_role_arn != null ? var.external_irsa_role_arn : aws_iam_role.aws_load_balancer_controller[0].arn
}

output "service_account_name" {
  description = "Name of the AWS Load Balancer Controller service account"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
}
