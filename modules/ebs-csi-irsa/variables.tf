variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_account_name" {
  description = "Name of the service account"
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "service_account_namespace" {
  description = "Namespace of the service account"
  type        = string
  default     = "kube-system"
}
