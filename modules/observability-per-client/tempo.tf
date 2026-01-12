# =============================================================================
# Tempo - Distributed Tracing
# =============================================================================
# Tempo deployment with S3 backend storage
# Supports: OTLP (gRPC/HTTP), Jaeger (multiple protocols), Zipkin
# =============================================================================

resource "helm_release" "tempo" {
  count      = var.enable_tempo ? 1 : 0
  name       = "${var.client_name}-tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.23.3"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      # ==========================================================================
      # Health Probes Configuration
      # ==========================================================================
      livenessProbe = {
        httpGet = {
          path   = "/ready"
          port   = 3100
          scheme = "HTTP"
        }
        initialDelaySeconds = 45
        periodSeconds       = 15
        timeoutSeconds      = 10
        failureThreshold    = 5
        successThreshold    = 1
      }

      readinessProbe = {
        httpGet = {
          path   = "/ready"
          port   = 3100
          scheme = "HTTP"
        }
        initialDelaySeconds = 30
        periodSeconds       = 10
        timeoutSeconds      = 10
        failureThreshold    = 3
        successThreshold    = 1
      }

      # ==========================================================================
      # Resource Configuration
      # ==========================================================================
      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      # ==========================================================================
      # Service Account with IRSA
      # ==========================================================================
      serviceAccount = {
        create = true
        name   = "tempo"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.enable_tempo ? aws_iam_role.tempo[0].arn : ""
        }
      }

      # ==========================================================================
      # Persistent Storage for WAL
      # ==========================================================================
      persistence = {
        enabled          = true
        storageClassName = "gp2-csi"
        size             = "20Gi"
        accessModes      = ["ReadWriteOnce"]
      }

      # ==========================================================================
      # Tempo Configuration
      # ==========================================================================
      tempo = {
        # Server configuration
        server = {
          http_listen_port = 3100
          grpc_listen_port = 9095
          log_level        = "info"
          log_format       = "json"
        }

        # S3 Storage Backend
        storage = {
          trace = {
            backend = "s3"
            s3 = {
              bucket               = var.shared_traces_bucket
              region               = var.region
              endpoint             = "s3.${var.region}.amazonaws.com"
              prefix               = local.traces_prefix
              insecure             = false
              part_size            = 5242880  # 5MB
              hedge_requests_at    = "500ms"
              hedge_requests_up_to = 3
            }
            wal = {
              path = "/var/tempo/wal"
            }
          }
        }

        # Receiver Configuration - All Protocols
        receivers = {
          # OTLP (OpenTelemetry Protocol)
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
                cors = {
                  allowed_origins = ["*"]
                }
              }
            }
          }

          # Jaeger
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250"
              }
              thrift_http = {
                endpoint = "0.0.0.0:14268"
              }
              thrift_compact = {
                endpoint = "0.0.0.0:6831"
              }
              thrift_binary = {
                endpoint = "0.0.0.0:6832"
              }
            }
          }

          # Zipkin
          zipkin = {
            endpoint = "0.0.0.0:9411"
            cors = {
              allowed_origins = ["*"]
            }
          }
        }

        # Performance Tuning
        ingester = {
          trace_idle_period      = "10s"
          max_block_duration     = "5m"
          flush_check_period     = "10s"
          max_block_bytes        = 1048576  # 1MB
          complete_block_timeout = "5m"
        }

        # Compactor Configuration
        compactor = {
          compaction = {
            block_retention = "${var.tempo_retention_hours}h"
          }
        }

        # Stability Settings
        multitenancyEnabled = false
        reportingEnabled    = false
        memBallastSizeMbs   = 1024

        # Data retention
        retention = "${var.tempo_retention_hours}h"
      }

      # ==========================================================================
      # Service Configuration
      # ==========================================================================
      service = {
        type = "ClusterIP"
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3100"
          "prometheus.io/path"   = "/metrics"
        }
      }

      # ==========================================================================
      # ServiceMonitor for Prometheus
      # ==========================================================================
      serviceMonitor = {
        enabled = true
        labels = {
          release   = "${var.client_name}-prometheus"
          component = "tempo"
        }
        interval = "15s"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack,
    aws_iam_role.tempo
  ]
}
