output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "ebs_csi_addon_arn" {
  description = "ARN of the EBS CSI driver addon"
  value       = aws_eks_addon.ebs_csi_driver.arn
}

output "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon"
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}

output "gp2_storageclass_name" {
  description = "Name of the GP2 StorageClass"
  value       = var.create_gp2_storageclass ? kubernetes_storage_class_v1.gp2[0].metadata[0].name : null
}

output "gp3_storageclass_name" {
  description = "Name of the GP3 StorageClass"
  value       = var.create_gp3_storageclass ? kubernetes_storage_class_v1.gp3[0].metadata[0].name : null
}

output "available_storageclasses" {
  description = "List of available StorageClass names"
  value = compact([
    var.create_gp2_storageclass ? "gp2" : null,
    var.create_gp3_storageclass ? "gp3" : null
  ])
}
