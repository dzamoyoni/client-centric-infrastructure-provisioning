# =============================================================================
# ISTIO SERVICE MESH MODULE OUTPUTS
# =============================================================================

# =============================================================================
# ISTIO SYSTEM INFORMATION
# =============================================================================

output "istio_system_namespace" {
  description = "Istio system namespace name"
  value       = kubernetes_namespace.istio_system.metadata[0].name
}

output "istio_ingress_namespace" {
  description = "Istio ingress namespace name (now deployed to istio-system)"
  value       = var.enable_ingress_gateway ? kubernetes_namespace.istio_system.metadata[0].name : null
}

output "istio_version" {
  description = "Deployed Istio version"
  value       = local.istio_version
}

output "mesh_id" {
  description = "Istio mesh ID"
  value       = var.mesh_id
}

# =============================================================================
# HELM RELEASE INFORMATION
# =============================================================================

output "helm_releases" {
  description = "Information about deployed Helm releases"
  value = {
    istio_base = {
      name      = helm_release.istio_base.name
      namespace = helm_release.istio_base.namespace
      version   = helm_release.istio_base.version
      status    = helm_release.istio_base.status
    }
    istiod = {
      name      = helm_release.istiod.name
      namespace = helm_release.istiod.namespace
      version   = helm_release.istiod.version
      status    = helm_release.istiod.status
    }
    istio_cni = var.enable_ambient_mode ? {
      name      = helm_release.istio_cni[0].name
      namespace = helm_release.istio_cni[0].namespace
      version   = helm_release.istio_cni[0].version
      status    = helm_release.istio_cni[0].status
    } : null
    ztunnel = var.enable_ambient_mode ? {
      name      = helm_release.ztunnel[0].name
      namespace = helm_release.ztunnel[0].namespace
      version   = helm_release.ztunnel[0].version
      status    = helm_release.ztunnel[0].status
    } : null
    istio_ingress_gateway = var.enable_ingress_gateway ? {
      deployment_name = kubernetes_deployment.istio_ingressgateway[0].metadata[0].name
      namespace       = kubernetes_deployment.istio_ingressgateway[0].metadata[0].namespace
      service_name    = kubernetes_service.istio_ingressgateway[0].metadata[0].name
      replicas        = kubernetes_deployment.istio_ingressgateway[0].spec[0].replicas
    } : null
  }
}

# =============================================================================
# SERVICE INFORMATION
# =============================================================================

output "ingress_gateway_service" {
  description = "Ingress gateway service information"
  value = var.enable_ingress_gateway ? {
    name      = "istio-ingressgateway"
    namespace = kubernetes_namespace.istio_system.metadata[0].name
    type      = "ClusterIP"
    ports     = var.ingress_gateway_ports
  } : null
}

output "istiod_service" {
  description = "Istiod service information"
  value = {
    name      = "istiod"
    namespace = kubernetes_namespace.istio_system.metadata[0].name
  }
}

# =============================================================================
# APPLICATION NAMESPACE INFORMATION
# =============================================================================

output "application_namespaces" {
  description = "Created application namespaces and their configuration"
  value = {
    for ns_name, ns_config in var.application_namespaces : ns_name => {
      name           = kubernetes_namespace.application_namespaces[ns_name].metadata[0].name
      dataplane_mode = ns_config.dataplane_mode
      client         = lookup(ns_config, "client", "unknown")
      tenant         = lookup(ns_config, "tenant", ns_name)
      labels         = kubernetes_namespace.application_namespaces[ns_name].metadata[0].labels
    }
  }
}

# =============================================================================
# AMBIENT MODE INFORMATION
# =============================================================================

output "ambient_mode_enabled" {
  description = "Whether ambient mode is enabled"
  value       = var.enable_ambient_mode
}

output "ambient_namespaces" {
  description = "Namespaces configured for ambient mode"
  value = [
    for ns_name, ns_config in var.application_namespaces : ns_name
    if ns_config.dataplane_mode == "ambient"
  ]
}

output "sidecar_namespaces" {
  description = "Namespaces configured for sidecar mode"
  value = [
    for ns_name, ns_config in var.application_namespaces : ns_name
    if ns_config.dataplane_mode == "sidecar"
  ]
}

# =============================================================================
# INTEGRATION ENDPOINTS
# =============================================================================

output "integration_info" {
  description = "Integration information for other layers and applications"
  value = {
    # For applications to configure Istio ingress
    ingress_gateway_endpoint = var.enable_ingress_gateway ? {
      service   = "istio-ingressgateway.${kubernetes_namespace.istio_system.metadata[0].name}.svc.cluster.local"
      namespace = kubernetes_namespace.istio_system.metadata[0].name
      ports = {
        http  = 80
        https = 443
      }
    } : null

    # For observability integration
    telemetry_endpoints = {
      tempo_endpoint          = "tempo.istio-system.svc.cluster.local:4317"
      prometheus_metrics_path = "/stats/prometheus"
    }

    # For application configuration
    mesh_config = {
      mesh_id      = var.mesh_id
      trust_domain = var.trust_domain
      cluster_name = var.cluster_name
      region       = var.region
    }
  }
}

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

output "monitoring_configuration" {
  description = "Monitoring configuration for integration with existing observability stack"
  value = {
    service_monitor_enabled  = var.enable_service_monitor
    prometheus_rules_enabled = var.enable_prometheus_rules
    tracing_enabled          = var.enable_distributed_tracing
    access_logging_enabled   = var.enable_access_logging
    tracing_sampling_rate    = var.tracing_sampling_rate
  }
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed components"
  value = {
    istio_version = local.istio_version
    components = {
      base_installed            = true
      istiod_installed          = true
      cni_installed             = var.enable_ambient_mode
      ztunnel_installed         = var.enable_ambient_mode
      ingress_gateway_installed = var.enable_ingress_gateway
    }
    namespaces = {
      istio_system  = kubernetes_namespace.istio_system.metadata[0].name
      istio_ingress = var.enable_ingress_gateway ? kubernetes_namespace.istio_system.metadata[0].name : "not-created"
    }
    features = {
      ambient_mode_enabled        = var.enable_ambient_mode
      distributed_tracing_enabled = var.enable_distributed_tracing
      access_logging_enabled      = var.enable_access_logging
      service_monitor_enabled     = var.enable_service_monitor
      prometheus_rules_enabled    = var.enable_prometheus_rules
    }
    application_namespaces = length(var.application_namespaces)
  }
}

# =============================================================================
# SSM PARAMETER OUTPUTS (FOR OTHER LAYERS)
# =============================================================================

output "ssm_parameter_names" {
  description = "SSM parameter names for integration with other layers"
  value = {
    mesh_id                  = "/${var.project_name}/${var.environment}/${var.region}/istio/mesh-id"
    istio_version            = "/${var.project_name}/${var.environment}/${var.region}/istio/version"
    ingress_gateway_endpoint = "/${var.project_name}/${var.environment}/${var.region}/istio/ingress-gateway-endpoint"
    ambient_mode_enabled     = "/${var.project_name}/${var.environment}/${var.region}/istio/ambient-mode-enabled"
  }
}
