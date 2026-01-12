output "iam_role_arn" {
  description = "ARN of the IAM role for ExternalDNS"
  value       = aws_iam_role.external_dns.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for ExternalDNS"
  value       = aws_iam_role.external_dns.name
}

output "service_account_name" {
  description = "Name of the service account for ExternalDNS"
  value       = var.service_account_name
}

output "service_account_namespace" {
  description = "Namespace of the service account for ExternalDNS"
  value       = var.service_account_namespace
}
