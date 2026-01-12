output "alb_ingress_class_name" {
  description = "Name of the ALB IngressClass"
  value       = kubernetes_ingress_class_v1.alb.metadata[0].name
}

output "nlb_ingress_class_name" {
  description = "Name of the NLB IngressClass"
  value       = var.create_nlb_ingress_class ? kubernetes_ingress_class_v1.nlb[0].metadata[0].name : null
}

output "nginx_ingress_class_name" {
  description = "Name of the nginx IngressClass"
  value       = var.create_nginx_ingress_class ? kubernetes_ingress_class_v1.nginx[0].metadata[0].name : null
}

output "default_ingress_class" {
  description = "Name of the default IngressClass"
  value       = var.set_as_default ? kubernetes_ingress_class_v1.alb.metadata[0].name : null
}
