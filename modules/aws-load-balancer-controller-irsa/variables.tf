variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_account_name" {
  description = "Name of the service account for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "service_account_namespace" {
  description = "Namespace of the service account for AWS Load Balancer Controller"
  type        = string
  default     = "kube-system"
}
