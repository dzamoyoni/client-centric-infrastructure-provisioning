# =============================================================================
# Prometheus Stack - kube-prometheus-stack
# =============================================================================
# Complete metrics, monitoring, and alerting stack
# Includes: Prometheus, Grafana, AlertManager, Node Exporter, Kube State Metrics
# =============================================================================

resource "helm_release" "prometheus_stack" {
  name       = "${var.client_name}-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      # ==========================================================================
      # Prometheus Configuration
      # ==========================================================================
      prometheus = {
        prometheusSpec = {
          # Client-specific external labels
          externalLabels = {
            client      = var.client_name
            tier        = var.client_tier
            cluster     = var.cluster_name
            environment = var.environment
          }

          # High Availability (based on tier)
          replicas = var.prometheus_replicas

          # Anti-affinity for HA (if multiple replicas)
          affinity = var.prometheus_replicas > 1 ? {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchExpressions = [{
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["prometheus"]
                    }]
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }]
            }
          } : {}

          # Storage configuration
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2-csi"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage
                  }
                }
              }
            }
          }

          # Data retention
          retention     = var.prometheus_retention
          retentionSize = var.prometheus_retention_size

          # Resource limits - single node group (no special scheduling)
          resources = {
            limits = {
              cpu    = "4000m"
              memory = "8Gi"
            }
            requests = {
              cpu    = "1000m"
              memory = "4Gi"
            }
          }

          # Remote write (optional)
          remoteWrite = var.prometheus_remote_write_url != "" ? [{
            url = var.prometheus_remote_write_url
          }] : []

          # Scrape configs - monitor this client's namespace
          additionalScrapeConfigs = [{
            job_name = "${var.client_name}-pods"
            kubernetes_sd_configs = [{
              role = "pod"
              namespaces = {
                names = [local.namespace, "kube-system"]
              }
            }]
            relabel_configs = [{
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
              action        = "keep"
              regex         = "true"
            }]
          }]
        }
      }

      # ==========================================================================
      # AlertManager Configuration
      # ==========================================================================
      alertmanager = {
        alertmanagerSpec = {
          # HA (based on tier)
          replicas = var.alertmanager_replicas

          # Storage
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2-csi"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }

          # Resource limits
          resources = {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        # Alert routing configuration
        config = {
          route = {
            group_by        = ["alertname", "client"]
            group_wait      = "10s"
            group_interval  = "10s"
            repeat_interval = "12h"
            receiver        = "${var.client_name}-alerts"
          }
          receivers = [{
            name = "${var.client_name}-alerts"
            email_configs = var.alert_email != "" ? [{
              to      = var.alert_email
              subject = "[${var.client_name}] {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
            }] : []
            slack_configs = var.slack_webhook_url != "" ? [{
              api_url = var.slack_webhook_url
              channel = "#${var.client_name}-alerts"
              title   = "[${var.client_name}] {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
            }] : []
          }]
        }
      }

      # ==========================================================================
      # Grafana Configuration
      # ==========================================================================
      grafana = {
        # Persistence
        persistence = {
          enabled          = true
          storageClassName = "gp2-csi"
          size             = var.grafana_storage
        }

        # Resource limits
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "2Gi"
          }
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
        }

        # Admin credentials
        adminPassword = var.grafana_admin_password

        # Service configuration
        service = {
          type = "ClusterIP"
          port = 80
        }

        # Grafana configuration
        "grafana.ini" = {
          server = {
            root_url = "http://localhost:3000"
            domain   = "localhost"
          }
          "auth.anonymous" = {
            enabled = false
          }
        }

        # Datasources - per-client services
        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = concat(
              [{
                name      = "Prometheus"
                type      = "prometheus"
                url       = "http://${var.client_name}-prometheus-prometheus.${local.namespace}.svc.cluster.local:9090"
                access    = "proxy"
                isDefault = true
                uid       = "prometheus"
              }],
              var.enable_loki ? [{
                name   = "Loki"
                type   = "loki"
                url    = "http://${var.client_name}-loki-gateway.${local.namespace}.svc.cluster.local:80"
                access = "proxy"
                uid    = "loki"
              }] : [],
              var.enable_tempo ? [{
                name   = "Tempo"
                type   = "tempo"
                url    = "http://${var.client_name}-tempo.${local.namespace}.svc.cluster.local:3100"
                access = "proxy"
                uid    = "tempo"
              }] : []
            )
          }
        }

        # Pre-configured dashboards
        dashboards = {
          default = {
            kubernetes-cluster = {
              gnetId     = 7249
              datasource = "Prometheus"
            }
            kubernetes-pods = {
              gnetId     = 6336
              datasource = "Prometheus"
            }
          }
        }
      }

      # ==========================================================================
      # Node Exporter - DaemonSet on ALL nodes
      # ==========================================================================
      nodeExporter = {
        enabled = var.enable_node_exporter

        # DaemonSet tolerations - runs on ALL nodes
        tolerations = [{
          operator = "Exists"
        }]

        # Light resource limits
        resources = {
          limits = {
            cpu    = "200m"
            memory = "200Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }

        hostNetwork = true
        hostPID     = true
      }

      # ==========================================================================
      # Kube State Metrics
      # ==========================================================================
      kubeStateMetrics = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # ==========================================================================
      # Default Prometheus Rules
      # ==========================================================================
      defaultRules = {
        create = true
        rules = {
          alertmanager                  = true
          etcd                          = false  # EKS managed
          general                       = true
          k8s                           = true
          kubeApiserver                 = true
          kubeApiserverAvailability     = true
          kubeApiserverBurnrate         = true
          kubeApiserverHistogram        = true
          kubeApiserverSlos             = true
          kubelet                       = true
          kubeProxy                     = true
          kubernetesApps                = true
          kubernetesResources           = true
          kubernetesStorage             = true
          kubernetesSystem              = true
          node                          = true
          nodeExporterAlerting          = true
          nodeExporterRecording         = true
          prometheus                    = true
          prometheusOperator            = true
        }
      }

      # Disable EKS-managed components
      kubeControllerManager = { enabled = false }
      kubeEtcd              = { enabled = false }
      kubeScheduler         = { enabled = false }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_storage_class_v1.gp2_csi
  ]
}
