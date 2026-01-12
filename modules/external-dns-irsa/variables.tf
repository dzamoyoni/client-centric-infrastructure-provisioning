variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for ExternalDNS"
  type        = string
  default     = "external-dns"
}

variable "service_account_namespace" {
  description = "Kubernetes namespace for the ExternalDNS service account"
  type        = string
  default     = "kube-system"
}

variable "route53_zone_arns" {
  description = "List of Route53 hosted zone ARNs that ExternalDNS can manage"
  type        = list(string)
}

variable "enable_txt_ownership_id" {
  description = "Enable TXT record ownership for multi-tenant ExternalDNS setups"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
