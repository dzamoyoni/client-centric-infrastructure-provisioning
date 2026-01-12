# =============================================================================
# Monitoring Namespace - Per Client
# =============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = local.namespace
    
    labels = merge(local.common_labels, {
      "name"         = local.namespace
      "client"       = var.client_name
      "tier"         = var.client_tier
      "client-code"  = var.client_code
      "cost-center"  = var.cost_center
      "business-unit" = var.business_unit
    })
    
    annotations = {
      "managed-by" = "terraform"
      "client"     = var.client_name
      "tier"       = var.client_tier
    }
  }
}
