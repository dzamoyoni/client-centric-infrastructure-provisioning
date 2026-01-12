variable "alb_ingress_class_name" {
  description = "Name for the ALB IngressClass"
  type        = string
  default     = "alb"
}

variable "nlb_ingress_class_name" {
  description = "Name for the NLB IngressClass"
  type        = string
  default     = "nlb"
}

variable "nginx_ingress_class_name" {
  description = "Name for the nginx IngressClass"
  type        = string
  default     = "nginx"
}

variable "set_as_default" {
  description = "Whether to set the ALB IngressClass as default"
  type        = bool
  default     = true
}

variable "create_nlb_ingress_class" {
  description = "Whether to create NLB IngressClass"
  type        = bool
  default     = false
}

variable "create_nginx_ingress_class" {
  description = "Whether to create nginx IngressClass"
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Kubernetes namespace for IngressClass parameters"
  type        = string
  default     = "kube-system"
}

variable "nlb_scheme" {
  description = "Scheme for NLB (internet-facing or internal)"
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.nlb_scheme)
    error_message = "NLB scheme must be either 'internet-facing' or 'internal'."
  }
}

variable "controller_parameters" {
  description = "Additional parameters for the IngressClass controller"
  type = list(object({
    api_group = string
    kind      = string
    name      = string
  }))
  default = []
}
