# =============================================================================
# ISTIO SERVICE MESH MODULE VARIABLES - PRODUCTION GRADE
# =============================================================================

# =============================================================================
# CORE CONFIGURATION
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "client-centric-client-eks"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# ISTIO CONFIGURATION
# =============================================================================

variable "istio_version" {
  description = "Version of Istio to deploy"
  type        = string
  default     = "1.27.1" # Updated to latest stable with ambient improvements
}

variable "mesh_id" {
  description = "Mesh ID for Istio"
  type        = string
  default     = "mesh1"
}

variable "cluster_network" {
  description = "Network identifier for the cluster"
  type        = string
  default     = "network1"
}

variable "trust_domain" {
  description = "Trust domain for Istio"
  type        = string
  default     = "cluster.local"
}

# =============================================================================
# AMBIENT MODE CONFIGURATION
# =============================================================================

variable "enable_ambient_mode" {
  description = "Enable Istio ambient mode"
  type        = bool
  default     = true
}

variable "enable_ambient_multicluster" {
  description = "Enable ambient multicluster support (Alpha in 1.27+)"
  type        = bool
  default     = false
}

variable "ambient_cni_istio_owned_config" {
  description = "Enable Istio-owned CNI config to prevent traffic bypass on node restart (1.27+ feature)"
  type        = bool
  default     = true
}

variable "ambient_cni_config_filename" {
  description = "Filename for Istio-owned CNI config (must have higher lexicographical priority than primary CNI)"
  type        = string
  default     = "02-istio-cni.conflist"
}

# =============================================================================
# INGRESS GATEWAY CONFIGURATION
# =============================================================================

variable "enable_ingress_gateway" {
  description = "Enable Istio ingress gateway"
  type        = bool
  default     = true
}

variable "ingress_gateway_replicas" {
  description = "Number of ingress gateway replicas"
  type        = number
  default     = 3
}

variable "ingress_gateway_resources" {
  description = "Resource configuration for ingress gateway"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "200m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}

variable "ingress_gateway_ports" {
  description = "Ports configuration for ingress gateway"
  type = list(object({
    name       = string
    port       = number
    targetPort = number
    protocol   = string
  }))
  default = [
    {
      name       = "http2"
      port       = 80
      targetPort = 8080
      protocol   = "TCP"
    },
    {
      name       = "https"
      port       = 443
      targetPort = 8443
      protocol   = "TCP"
    }
  ]
}

variable "ingress_gateway_service_annotations" {
  description = "Service annotations for ingress gateway"
  type        = map(string)
  default     = {}
}

variable "ingress_gateway_autoscale_enabled" {
  description = "Enable autoscaling for ingress gateway"
  type        = bool
  default     = true
}

variable "ingress_gateway_autoscale_min" {
  description = "Minimum replicas for ingress gateway autoscaling"
  type        = number
  default     = 2
}

variable "ingress_gateway_autoscale_max" {
  description = "Maximum replicas for ingress gateway autoscaling"
  type        = number
  default     = 10
}

variable "ingress_gateway_autoscale_cpu_target" {
  description = "CPU utilization target for ingress gateway autoscaling"
  type        = number
  default     = 80
}

variable "ingress_gateway_node_selector" {
  description = "Node selector for ingress gateway pods"
  type        = map(string)
  default     = {}
}

variable "ingress_gateway_tolerations" {
  description = "Tolerations for ingress gateway pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "ingress_gateway_pdb_enabled" {
  description = "Enable pod disruption budget for ingress gateway"
  type        = bool
  default     = true
}

variable "ingress_gateway_pdb_min_available" {
  description = "Minimum available replicas for ingress gateway PDB"
  type        = string
  default     = "50%"
}

variable "ingress_gateway_security_context" {
  description = "Security context for ingress gateway"
  type = object({
    runAsUser  = number
    runAsGroup = number
    fsGroup    = number
  })
  default = {
    runAsUser  = 1337
    runAsGroup = 1337
    fsGroup    = 1337
  }
}

# =============================================================================
# ISTIOD CONFIGURATION
# =============================================================================

variable "istiod_resources" {
  description = "Resource configuration for istiod"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "2Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "4Gi"
    }
  }
}

variable "istiod_autoscale_enabled" {
  description = "Enable autoscaling for istiod"
  type        = bool
  default     = true
}

variable "istiod_autoscale_min" {
  description = "Minimum replicas for istiod autoscaling"
  type        = number
  default     = 2
}

variable "istiod_autoscale_max" {
  description = "Maximum replicas for istiod autoscaling"
  type        = number
  default     = 5
}

# =============================================================================
# CNI CONFIGURATION
# =============================================================================

variable "cni_resources" {
  description = "Resource configuration for Istio CNI"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "100Mi"
    }
    limits = {
      cpu    = "1000m"
      memory = "1Gi"
    }
  }
}

variable "cni_node_selector" {
  description = "Node selector for CNI pods"
  type        = map(string)
  default     = {}
}

variable "cni_tolerations" {
  description = "Tolerations for CNI pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      value    = ""
      effect   = ""
    }
  ]
}

# =============================================================================
# ZTUNNEL CONFIGURATION
# =============================================================================

variable "ztunnel_resources" {
  description = "Resource configuration for ztunnel"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "200m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "2000m"
      memory = "1Gi"
    }
  }
}

variable "ztunnel_node_selector" {
  description = "Node selector for ztunnel pods"
  type        = map(string)
  default     = {}
}

variable "ztunnel_tolerations" {
  description = "Tolerations for ztunnel pods"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = [
    {
      key      = "node.kubernetes.io/not-ready"
      operator = "Exists"
      value    = ""
      effect   = "NoExecute"
    },
    {
      key      = "node.kubernetes.io/unreachable"
      operator = "Exists"
      value    = ""
      effect   = "NoExecute"
    }
  ]
}

variable "ztunnel_image" {
  description = "Ztunnel image configuration"
  type = object({
    repository = string
    tag        = string
    pullPolicy = string
  })
  default = {
    repository = "docker.io/istio/ztunnel"
    tag        = ""
    pullPolicy = "IfNotPresent"
  }
}

# =============================================================================
# APPLICATION NAMESPACE CONFIGURATION
# =============================================================================

variable "application_namespaces" {
  description = "Configuration for application namespaces"
  type = map(object({
    dataplane_mode = string # "ambient" or "sidecar"
    client         = optional(string)
    tenant         = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for ns_name, ns_config in var.application_namespaces :
      contains(["ambient", "sidecar"], ns_config.dataplane_mode)
    ])
    error_message = "Dataplane mode must be either 'ambient' or 'sidecar'."
  }
}

# =============================================================================
# OBSERVABILITY INTEGRATION (WITH EXISTING LAYER 03.5)
# =============================================================================

variable "enable_distributed_tracing" {
  description = "Enable distributed tracing integration with existing Tempo"
  type        = bool
  default     = true
}

variable "enable_access_logging" {
  description = "Enable access logging integration with existing Fluent Bit"
  type        = bool
  default     = true
}

variable "tracing_sampling_rate" {
  description = "Tracing sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.01

  validation {
    condition     = var.tracing_sampling_rate >= 0.0 && var.tracing_sampling_rate <= 1.0
    error_message = "Tracing sampling rate must be between 0.0 and 1.0."
  }
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

variable "enable_service_monitor" {
  description = "Enable ServiceMonitor for Prometheus integration"
  type        = bool
  default     = true
}

variable "enable_prometheus_rules" {
  description = "Enable PrometheusRules for alerting"
  type        = bool
  default     = true
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

variable "enable_default_telemetry" {
  description = "Enable default telemetry configuration"
  type        = bool
  default     = true
}
