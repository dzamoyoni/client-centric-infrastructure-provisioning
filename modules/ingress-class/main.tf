# IngressClass Management Module
# Creates and manages Kubernetes IngressClass resources

resource "kubernetes_ingress_class_v1" "alb" {
  metadata {
    name = var.alb_ingress_class_name

    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = var.set_as_default ? "true" : "false"
    }

    labels = {
      "app.kubernetes.io/name"       = "aws-load-balancer-controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    controller = "ingress.k8s.aws/alb"

    # Optional parameters for ALB controller
    dynamic "parameters" {
      for_each = var.controller_parameters
      content {
        api_group = parameters.value.api_group
        kind      = parameters.value.kind
        name      = parameters.value.name
      }
    }
  }
}

# Optional: Create NLB IngressClass if needed
resource "kubernetes_ingress_class_v1" "nlb" {
  count = var.create_nlb_ingress_class ? 1 : 0

  metadata {
    name = var.nlb_ingress_class_name

    labels = {
      "app.kubernetes.io/name"       = "aws-load-balancer-controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    controller = "ingress.k8s.aws/alb"

    parameters {
      api_group = "elbv2.k8s.aws"
      kind      = "IngressClassParams"
      name      = kubernetes_manifest.nlb_params[0].manifest.metadata.name
    }
  }

  depends_on = [kubernetes_manifest.nlb_params]
}

# IngressClassParams for NLB configuration
resource "kubernetes_manifest" "nlb_params" {
  count = var.create_nlb_ingress_class ? 1 : 0

  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "IngressClassParams"
    metadata = {
      name      = "${var.nlb_ingress_class_name}-params"
      namespace = var.namespace
    }
    spec = {
      scheme           = var.nlb_scheme
      loadBalancerType = "nlb"
    }
  }
}

# Optional: Create nginx IngressClass if using nginx alongside ALB
resource "kubernetes_ingress_class_v1" "nginx" {
  count = var.create_nginx_ingress_class ? 1 : 0

  metadata {
    name = var.nginx_ingress_class_name

    labels = {
      "app.kubernetes.io/name"       = "ingress-nginx"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    controller = "k8s.io/ingress-nginx"
  }
}
