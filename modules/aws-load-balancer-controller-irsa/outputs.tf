output "iam_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller IRSA"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "iam_role_name" {
  description = "IAM role name for the AWS Load Balancer Controller IRSA"
  value       = aws_iam_role.aws_load_balancer_controller.name
}

output "service_account_name" {
  description = "Service account name for AWS Load Balancer Controller"
  value       = var.service_account_name
}

output "service_account_namespace" {
  description = "Service account namespace for AWS Load Balancer Controller"
  value       = var.service_account_namespace
}
