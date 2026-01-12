output "iam_role_arn" {
  description = "IAM role ARN for the EBS CSI driver IRSA"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "iam_role_name" {
  description = "IAM role name for the EBS CSI driver IRSA"
  value       = aws_iam_role.ebs_csi_driver.name
}
