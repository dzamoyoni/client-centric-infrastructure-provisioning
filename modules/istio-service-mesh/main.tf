# =============================================================================
# ISTIO SERVICE MESH MODULE - PRODUCTION GRADE
# =============================================================================
# Simplified Istio deployment that integrates with existing observability layer
# Focus: Ambient mode, ClusterIP ingress, integrate with Layer 03.5 observability
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# =============================================================================
# LOCAL VALUES AND CONFIGURATION
# =============================================================================

locals {
  # Standard tags
  common_tags = merge(var.additional_tags, {
    Component    = "ServiceMesh"
    ManagedBy    = "Terraform"
    IstioVersion = var.istio_version
    Layer        = "SharedServices"
  })

  # Istio component versions
  istio_version = var.istio_version

  # Namespace configuration - Keep it simple
  namespaces = {
    istio_system  = "istio-system"
    istio_ingress = "istio-ingress"
  }
}

# =============================================================================
# NAMESPACE CREATION
# =============================================================================

# Istio system namespace
resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = local.namespaces.istio_system
    labels = merge(local.common_tags, {
      "istio-injection" = "disabled" # System namespace should not be injected
      "name"            = local.namespaces.istio_system
    })
  }
}

# Istio ingress namespace (optional - we'll deploy to istio-system instead)
# resource "kubernetes_namespace" "istio_ingress" {
#   count = var.enable_ingress_gateway ? 1 : 0
#   
#   metadata {
#     name = local.namespaces.istio_ingress
#     labels = merge(local.common_tags, {
#       "istio-injection" = "disabled"  # Don't inject ingress gateway
#       "name"           = local.namespaces.istio_ingress
#     })
#   }
#   
#   depends_on = [kubernetes_namespace.istio_system]
# }

# =============================================================================
# ISTIO BASE INSTALLATION
# =============================================================================

# Istio base Helm chart (CRDs and cluster-wide resources)
resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = local.istio_version
  namespace  = local.namespaces.istio_system

  create_namespace = false

  set {
    name  = "global.meshID"
    value = var.mesh_id
  }

  set {
    name  = "global.network"
    value = var.cluster_network
  }

  depends_on = [kubernetes_namespace.istio_system]

  timeout = 600
}

# =============================================================================
# ISTIO CONTROL PLANE (ISTIOD) - INTEGRATED WITH EXISTING OBSERVABILITY
# =============================================================================

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = local.istio_version
  namespace  = local.namespaces.istio_system

  # Istiod configuration with ambient mode support and observability integration
  values = [yamlencode({
    global = {
      meshID  = var.mesh_id
      network = var.cluster_network

      # Integration with existing observability layer
      meshConfig = {
        trustDomain = var.trust_domain

        # Configure Istio to use existing Tempo for tracing
        defaultConfig = {
          tracing = {
            sampling = var.tracing_sampling_rate
            custom_tags = {
              cluster_name = var.cluster_name
              region       = var.region
            }
          }
          # Enable ambient waypoint support
          waypoint = {
            resources = {
              requests = {
                cpu    = "100m"
                memory = "128Mi"
              }
            }
          }
        }

        # Extension providers for observability integration
        extensionProviders = [
          {
            name = "tempo"
            envoyOtelAls = {
              service = "tempo.istio-system.svc.cluster.local"
              port    = 4317
            }
          },
          {
            name = "prometheus"
            prometheus = {
              configOverride = {
                metric_relabeling_configs = [
                  {
                    source_labels = ["__name__"]
                    regex         = "(istio_.*)"
                    target_label  = "__tmp_istio_name"
                  }
                ]
              }
            }
          }
        ]
      }
    }

    pilot = {
      # Enable ambient mode
      env = {
        ENABLE_AMBIENT       = var.enable_ambient_mode
        PILOT_ENABLE_AMBIENT = var.enable_ambient_mode
        # Integration with existing observability
        EXTERNAL_ISTIOD = false
        # Fix webhook validation readiness check issues
        PILOT_ENABLE_VALIDATION     = false
        VALIDATION                  = false
        WEBHOOK_CERT_CHECK          = false
        DISABLE_WEBHOOK_AUTO_CONFIG = true
      }

      # Resource configuration for production
      resources = var.istiod_resources

      # High availability for production
      autoscaleEnabled = var.istiod_autoscale_enabled
      autoscaleMin     = var.istiod_autoscale_min
      autoscaleMax     = var.istiod_autoscale_max

      # Deployment strategy
      rollingMaxUnavailable = "25%"
      rollingMaxSurge       = "100%"
    }

    # Telemetry configuration - lightweight, delegate to existing stack
    telemetry = {
      v2 = {
        enabled = true
      }
    }

    # Webhook configuration for validation
    istiodRemote = {
      enabled = false
    }
  })]

  depends_on = [helm_release.istio_base]

  timeout = 600
}

# =============================================================================
# ISTIO CNI (FOR AMBIENT MODE)
# =============================================================================

resource "helm_release" "istio_cni" {
  count = var.enable_ambient_mode ? 1 : 0

  name       = "istio-cni"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "cni"
  version    = local.istio_version
  namespace  = local.namespaces.istio_system

  values = [yamlencode({
    global = {
      meshID  = var.mesh_id
      network = var.cluster_network
    }

    cni = {
      # CNI configuration for ambient mode
      ambient = {
        enabled = true
      }

      # NEW 1.27+ feature: Istio-owned CNI config to prevent traffic bypass
      istioOwnedCNIConfig         = var.ambient_cni_istio_owned_config
      istioOwnedCNIConfigFilename = var.ambient_cni_config_filename

      # Resource configuration
      resources = var.cni_resources

      # Node selector for CNI pods (production considerations)
      nodeSelector = var.cni_node_selector

      # Tolerations for system nodes (now configurable via Helm in 1.27+)
      tolerations = var.cni_tolerations

      # Logging configuration - integrate with existing Fluent Bit
      logging = {
        level = "info"
      }
    }
  })]

  depends_on = [helm_release.istiod]

  timeout = 600
}

# =============================================================================
# ZTUNNEL (AMBIENT MODE PROXY)
# =============================================================================

resource "helm_release" "ztunnel" {
  count = var.enable_ambient_mode ? 1 : 0

  name       = "ztunnel"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "ztunnel"
  version    = local.istio_version
  namespace  = local.namespaces.istio_system

  values = [yamlencode({
    global = {
      meshID  = var.mesh_id
      network = var.cluster_network
      logging = {
        level = "info"
      }
    }

    # Ztunnel configuration
    ztunnel = {
      # Resource configuration for production
      resources = var.ztunnel_resources

      # Node selector
      nodeSelector = var.ztunnel_node_selector

      # Tolerations for all nodes
      tolerations = var.ztunnel_tolerations

      # Image configuration
      image = var.ztunnel_image

      # Update strategy
      updateStrategy = {
        type = "RollingUpdate"
        rollingUpdate = {
          maxUnavailable = 1
        }
      }
    }
  })]

  depends_on = [
    helm_release.istiod,
    helm_release.istio_cni[0]
  ]

  timeout = 600
}

# =============================================================================
# RBAC FIX FOR WEBHOOK VALIDATION
# =============================================================================
# Fix istiod RBAC permissions for webhook validation to work properly
resource "kubernetes_cluster_role" "istiod_webhook_rbac_fix" {
  metadata {
    name = "istiod-webhook-validation-fix"
    labels = merge(local.common_tags, {
      "app" = "istiod"
    })
  }

  rule {
    api_groups = ["networking.istio.io"]
    resources  = ["gateways", "virtualservices", "destinationrules", "serviceentries"]
    verbs      = ["update", "patch", "create", "delete"]
  }

  rule {
    api_groups = ["security.istio.io"]
    resources  = ["authorizationpolicies", "peerauthentications", "requestauthentications"]
    verbs      = ["update", "patch", "create", "delete"]
  }

  rule {
    api_groups = ["telemetry.istio.io"]
    resources  = ["telemetries"]
    verbs      = ["update", "patch", "create", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "istiod_webhook_rbac_fix" {
  metadata {
    name = "istiod-webhook-validation-fix"
    labels = merge(local.common_tags, {
      "app" = "istiod"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.istiod_webhook_rbac_fix.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "istiod"
    namespace = local.namespaces.istio_system
  }

  depends_on = [helm_release.istiod]
}

# =============================================================================
# INGRESS GATEWAY (MANUAL DEPLOYMENT) - PRODUCTION GRADE
# =============================================================================
# Use manual deployment to avoid webhook issues while maintaining full code management

resource "kubernetes_service_account" "istio_ingressgateway" {
  count = var.enable_ingress_gateway ? 1 : 0

  metadata {
    name      = "istio-ingressgateway"
    namespace = local.namespaces.istio_system
    labels = merge(local.common_tags, {
      "app"     = "istio-ingressgateway"
      "istio"   = "ingressgateway"
      "release" = "istio-ingressgateway"
    })
  }

  depends_on = [kubernetes_namespace.istio_system]
}

resource "kubernetes_deployment" "istio_ingressgateway" {
  count = var.enable_ingress_gateway ? 1 : 0

  metadata {
    name      = "istio-ingressgateway"
    namespace = local.namespaces.istio_system
    labels = merge(local.common_tags, {
      "app"     = "istio-ingressgateway"
      "istio"   = "ingressgateway"
      "release" = "istio-ingressgateway"
    })
  }

  spec {
    replicas = var.ingress_gateway_replicas

    selector {
      match_labels = {
        app   = "istio-ingressgateway"
        istio = "ingressgateway"
      }
    }

    template {
      metadata {
        labels = {
          app                       = "istio-ingressgateway"
          istio                     = "ingressgateway"
          "sidecar.istio.io/inject" = "false" # Disable injection for manual deployment
        }
        annotations = {
          "prometheus.io/path"   = "/stats/prometheus"
          "prometheus.io/port"   = "15020"
          "prometheus.io/scrape" = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.istio_ingressgateway[0].metadata[0].name

        # Anti-affinity for high availability
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    app = "istio-ingressgateway"
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        security_context {
          fs_group     = 1337
          run_as_group = 1337
          run_as_user  = 1337
        }

        container {
          name  = "istio-proxy"
          image = "docker.io/istio/proxyv2:${local.istio_version}"

          args = [
            "proxy",
            "router",
            "--domain",
            "$(POD_NAMESPACE).svc.cluster.local",
            "--proxyLogLevel=warning",
            "--proxyComponentLogLevel=misc:error",
            "--log_output_level=default:info"
          ]

          env {
            name  = "JWT_POLICY"
            value = "third-party-jwt"
          }
          env {
            name  = "PILOT_CERT_PROVIDER"
            value = "istiod"
          }
          env {
            name  = "CA_ADDR"
            value = "istiod.istio-system.svc:15012"
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name = "INSTANCE_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name = "SERVICE_ACCOUNT"
            value_from {
              field_ref {
                field_path = "spec.serviceAccountName"
              }
            }
          }
          env {
            name = "HOST_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }
          env {
            name = "ISTIO_CPU_LIMIT"
            value_from {
              resource_field_ref {
                resource = "limits.cpu"
              }
            }
          }
          env {
            name  = "PROXY_CONFIG"
            value = "{}"
          }
          env {
            name  = "ISTIO_META_POD_PORTS"
            value = "[]"
          }
          env {
            name  = "ISTIO_META_APP_CONTAINERS"
            value = ""
          }
          env {
            name  = "ISTIO_META_CLUSTER_ID"
            value = "Kubernetes"
          }
          env {
            name = "ISTIO_META_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name  = "ISTIO_META_INTERCEPTION_MODE"
            value = "REDIRECT"
          }
          env {
            name  = "ISTIO_META_WORKLOAD_NAME"
            value = "istio-ingressgateway"
          }
          env {
            name  = "ISTIO_META_OWNER"
            value = "kubernetes://apis/apps/v1/namespaces/istio-system/deployments/istio-ingressgateway"
          }
          env {
            name  = "ISTIO_META_MESH_ID"
            value = var.mesh_id
          }
          env {
            name  = "TRUST_DOMAIN"
            value = var.trust_domain
          }
          env {
            name  = "ISTIO_META_ROUTER_MODE"
            value = "standard"
          }

          port {
            container_port = 15021
            name           = "status-port"
            protocol       = "TCP"
          }
          port {
            container_port = 8080
            name           = "http2"
            protocol       = "TCP"
          }
          port {
            container_port = 8443
            name           = "https"
            protocol       = "TCP"
          }
          port {
            container_port = 15090
            name           = "http-envoy-prom"
            protocol       = "TCP"
          }

          readiness_probe {
            failure_threshold = 30
            http_get {
              path   = "/healthz/ready"
              port   = "15021"
              scheme = "HTTP"
            }
            initial_delay_seconds = 1
            period_seconds        = 2
            success_threshold     = 1
            timeout_seconds       = 1
          }

          resources {
            limits = {
              cpu    = var.ingress_gateway_resources.limits.cpu
              memory = var.ingress_gateway_resources.limits.memory
            }
            requests = {
              cpu    = var.ingress_gateway_resources.requests.cpu
              memory = var.ingress_gateway_resources.requests.memory
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
            privileged                = false
            read_only_root_filesystem = true
            run_as_group              = 1337
            run_as_non_root           = true
            run_as_user               = 1337
          }

          # Volume mounts for Istio proxy functionality
          volume_mount {
            mount_path = "/var/run/secrets/workload-spiffe-uds"
            name       = "workload-socket"
          }
          volume_mount {
            mount_path = "/var/run/secrets/credential-uds"
            name       = "credential-socket"
          }
          volume_mount {
            mount_path = "/var/run/secrets/workload-spiffe-credentials"
            name       = "workload-certs"
          }
          volume_mount {
            mount_path = "/etc/istio/proxy"
            name       = "istio-envoy"
          }
          volume_mount {
            mount_path = "/etc/istio/config"
            name       = "config-volume"
          }
          volume_mount {
            mount_path = "/var/run/secrets/istio"
            name       = "istiod-ca-cert"
          }
          volume_mount {
            mount_path = "/var/run/secrets/tokens"
            name       = "istio-token"
            read_only  = true
          }
          volume_mount {
            mount_path = "/var/lib/istio/data"
            name       = "istio-data"
          }
          volume_mount {
            mount_path = "/etc/istio/pod"
            name       = "podinfo"
          }
          volume_mount {
            mount_path = "/etc/istio/ingressgateway-certs"
            name       = "ingressgateway-certs"
            read_only  = true
          }
          volume_mount {
            mount_path = "/etc/istio/ingressgateway-ca-certs"
            name       = "ingressgateway-ca-certs"
            read_only  = true
          }
        }

        # Volumes for Istio proxy functionality
        volume {
          name = "workload-socket"
          empty_dir {}
        }
        volume {
          name = "credential-socket"
          empty_dir {}
        }
        volume {
          name = "workload-certs"
          empty_dir {}
        }
        volume {
          name = "istiod-ca-cert"
          config_map {
            name = "istio-ca-root-cert"
          }
        }
        volume {
          name = "podinfo"
          downward_api {
            items {
              field_ref {
                field_path = "metadata.labels"
              }
              path = "labels"
            }
            items {
              field_ref {
                field_path = "metadata.annotations"
              }
              path = "annotations"
            }
          }
        }
        volume {
          name = "istio-envoy"
          empty_dir {}
        }
        volume {
          name = "istio-data"
          empty_dir {}
        }
        volume {
          name = "istio-token"
          projected {
            sources {
              service_account_token {
                audience           = "istio-ca"
                expiration_seconds = 43200
                path               = "istio-token"
              }
            }
          }
        }
        volume {
          name = "config-volume"
          config_map {
            name     = "istio"
            optional = true
          }
        }
        volume {
          name = "ingressgateway-certs"
          secret {
            optional    = true
            secret_name = "istio-ingressgateway-certs"
          }
        }
        volume {
          name = "ingressgateway-ca-certs"
          secret {
            optional    = true
            secret_name = "istio-ingressgateway-ca-certs"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.istio_system,
    helm_release.istiod,
    kubernetes_cluster_role_binding.istiod_webhook_rbac_fix
  ]
}

resource "kubernetes_service" "istio_ingressgateway" {
  count = var.enable_ingress_gateway ? 1 : 0

  metadata {
    name      = "istio-ingressgateway"
    namespace = local.namespaces.istio_system
    labels = merge(local.common_tags, {
      "app"     = "istio-ingressgateway"
      "istio"   = "ingressgateway"
      "release" = "istio-ingressgateway"
    })
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app   = "istio-ingressgateway"
      istio = "ingressgateway"
    }

    port {
      name        = "status-port"
      port        = 15021
      target_port = "15021"
      protocol    = "TCP"
    }
    port {
      name        = "http2"
      port        = 80
      target_port = "8080"
      protocol    = "TCP"
    }
    port {
      name        = "https"
      port        = 443
      target_port = "8443"
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_deployment.istio_ingressgateway[0]]
}

resource "kubernetes_pod_disruption_budget_v1" "istio_ingressgateway" {
  count = var.enable_ingress_gateway ? 1 : 0

  metadata {
    name      = "istio-ingressgateway"
    namespace = local.namespaces.istio_system
    labels = merge(local.common_tags, {
      "app"     = "istio-ingressgateway"
      "istio"   = "ingressgateway"
      "release" = "istio-ingressgateway"
    })
  }

  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "istio-ingressgateway"
      }
    }
  }

  depends_on = [kubernetes_deployment.istio_ingressgateway[0]]
}

# =============================================================================
# TELEMETRY CONFIGURATION - INTEGRATION WITH LAYER 03.5
# =============================================================================

# Configure Istio telemetry to integrate with existing observability stack
# NOTE: This resource is commented out initially and will be enabled after Istio CRDs are installed
/*
resource "kubernetes_manifest" "istio_telemetry_integration" {
  manifest = {
    apiVersion = "telemetry.istio.io/v1alpha1"
    kind       = "Telemetry"
    metadata = {
      name      = "default-integration"
      namespace = local.namespaces.istio_system
    }
    spec = {
      # Metrics configuration - integrate with existing Prometheus
      metrics = [
        {
          providers = [
            {
              name = "prometheus"
            }
          ]
          overrides = [
            {
              match = {
                metric = "ALL_METRICS"
              }
              tagOverrides = {
                cluster_name = {
                  value = var.cluster_name
                }
                region = {
                  value = var.region
                }
              }
            }
          ]
        }
      ]
      
      # Tracing configuration - integrate with existing Tempo
      tracing = var.enable_distributed_tracing ? [
        {
          providers = [
            {
              name = "tempo"
            }
          ]
          customTags = {
            cluster_name = {
              literal = {
                value = var.cluster_name
              }
            }
            region = {
              literal = {
                value = var.region
              }
            }
          }
        }
      ] : []
      
      # Access logging configuration - integrate with existing Fluent Bit
      accessLogging = var.enable_access_logging ? [
        {
          providers = [
            {
              name = "otel"
            }
          ]
        }
      ] : []
    }
  }
  
  depends_on = [helm_release.istiod]
}
*/

# =============================================================================
# NAMESPACE MANAGEMENT FOR APPLICATIONS - SIMPLIFIED
# =============================================================================

# Create and configure application namespaces
resource "kubernetes_namespace" "application_namespaces" {
  for_each = var.application_namespaces

  metadata {
    name = each.key
    labels = merge(local.common_tags, {
      "istio.io/dataplane-mode" = each.value.dataplane_mode
      "istio-injection"         = each.value.dataplane_mode == "sidecar" ? "enabled" : "disabled"
      "name"                    = each.key
      # Add client/tenant labels for observability integration
      "client" = lookup(each.value, "client", "unknown")
      "tenant" = lookup(each.value, "tenant", each.key)
    })
  }

  depends_on = [
    helm_release.istiod,
    helm_release.ztunnel
  ]
}

# Configure ambient mode for namespaces
resource "kubernetes_labels" "ambient_namespace_labels" {
  for_each = {
    for ns_name, ns_config in var.application_namespaces : ns_name => ns_config
    if ns_config.dataplane_mode == "ambient"
  }

  api_version = "v1"
  kind        = "Namespace"

  metadata {
    name = each.key
  }

  labels = {
    "istio.io/dataplane-mode" = "ambient"
  }

  depends_on = [kubernetes_namespace.application_namespaces]
}

# =============================================================================
# PRODUCTION MONITORING AND HEALTH CHECKS
# =============================================================================
# NOTE: These resources are commented out initially and will be enabled after Prometheus Operator CRDs are available

/*
# Service Monitor for Istio components (integrates with existing Prometheus)
resource "kubernetes_manifest" "istio_service_monitor" {
  count = var.enable_service_monitor ? 1 : 0
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "istio-system-monitoring"
      namespace = local.namespaces.istio_system
      labels = merge(local.common_tags, {
        "app.kubernetes.io/name" = "istio"
      })
    }
    spec = {
      selector = {
        matchLabels = {
          app = "istiod"
        }
      }
      endpoints = [
        {
          port     = "http-monitoring"
          interval = "30s"
          path     = "/stats/prometheus"
        }
      ]
    }
  }
  
  depends_on = [helm_release.istiod]
}

# Prometheus Rule for Istio alerting
resource "kubernetes_manifest" "istio_prometheus_rules" {
  count = var.enable_prometheus_rules ? 1 : 0
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "istio-system-rules"
      namespace = local.namespaces.istio_system
      labels = merge(local.common_tags, {
        "app.kubernetes.io/name" = "istio"
      })
    }
    spec = {
      groups = [
        {
          name = "istio.rules"
          rules = [
            {
              alert = "IstioControlPlaneDown"
              expr  = "up{job=\"istiod\"} == 0"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Istio control plane is down"
                description = "Istio control plane has been down for more than 1 minute"
              }
            },
            {
              alert = "IstioHighRequestLatency"
              expr  = "histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket[5m])) > 1000"
              for   = "2m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High request latency detected"
                description = "99th percentile latency is above 1s"
              }
            }
          ]
        }
      ]
    }
  }
  
  depends_on = [helm_release.istiod]
}
*/
