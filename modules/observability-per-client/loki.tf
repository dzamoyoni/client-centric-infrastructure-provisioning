# =============================================================================
# Loki Distributed - Log Aggregation
# =============================================================================
# Distributed Loki deployment with S3 backend storage
# Components: Ingester, Querier, Query Frontend, Compactor, Gateway, Memcached
# =============================================================================

resource "helm_release" "loki" {
  count      = var.enable_loki ? 1 : 0
  name       = "${var.client_name}-loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-distributed"
  version    = "0.80.5"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      # ==========================================================================
      # Loki Configuration with S3 Backend
      # ==========================================================================
      loki = {
        structuredConfig = {
          auth_enabled = false
          server = {
            http_listen_port = 3100
            grpc_listen_port = 9095
            log_level        = "info"
          }
          common = {
            path_prefix = local.logs_prefix
            storage = {
              s3 = {
                bucketnames      = var.shared_logs_bucket
                region           = var.region
                s3forcepathstyle = false
              }
            }
          }
          schema_config = {
            configs = [{
              from         = "2024-01-01"
              store        = "boltdb-shipper"
              object_store = "s3"
              schema       = "v12"
              index = {
                prefix = "loki_index_"
                period = "24h"
              }
            }]
          }
          limits_config = {
            ingestion_rate_strategy     = "global"
            ingestion_rate_mb           = 32
            ingestion_burst_size_mb     = 64
            max_global_streams_per_user = 10000
            max_query_length            = "12000h"
            retention_period            = "${var.loki_retention_days * 24}h"
            per_stream_rate_limit       = "10MB"
            per_stream_rate_limit_burst = "20MB"
          }
        }
      }

      # ==========================================================================
      # Ingester - Receives and writes logs to S3
      # ==========================================================================
      ingester = {
        replicas       = 1
        maxUnavailable = 0

        resources = {
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
        }

        serviceAccount = {
          create = true
          name   = "loki-ingester"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.enable_loki ? aws_iam_role.loki[0].arn : ""
          }
        }

        persistence = {
          enabled          = true
          storageClassName = "gp2-csi"
          size             = "10Gi"
        }
      }

      # ==========================================================================
      # Querier - Queries logs from S3
      # ==========================================================================
      querier = {
        replicas       = 1
        maxUnavailable = 0

        resources = {
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }

        serviceAccount = {
          create = true
          name   = "loki-querier"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.enable_loki ? aws_iam_role.loki[0].arn : ""
          }
        }
      }

      # ==========================================================================
      # Query Frontend - Load balancing for queries
      # ==========================================================================
      queryFrontend = {
        replicas       = 1
        maxUnavailable = 0

        resources = {
          limits = {
            cpu    = "100m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
        }
      }

      # ==========================================================================
      # Compactor - Compacts and manages retention
      # ==========================================================================
      compactor = {
        enabled = true

        resources = {
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }

        serviceAccount = {
          create = true
          name   = "loki-compactor"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.enable_loki ? aws_iam_role.loki[0].arn : ""
          }
        }

        persistence = {
          enabled          = true
          storageClassName = "gp2-csi"
          size             = "5Gi"
        }
      }

      # ==========================================================================
      # Gateway - Unified access point
      # ==========================================================================
      gateway = {
        enabled        = true
        replicas       = 1
        maxUnavailable = 0

        resources = {
          limits = {
            cpu    = "50m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "10m"
            memory = "32Mi"
          }
        }

        service = {
          type = "ClusterIP"
          port = 80
        }
      }

      # ==========================================================================
      # Memcached - Query result caching
      # ==========================================================================
      memcached = {
        enabled = true

        resources = {
          limits = {
            cpu    = "100m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
        }
      }

      # ==========================================================================
      # Service Monitor for Prometheus Integration
      # ==========================================================================
      serviceMonitor = {
        enabled   = true
        namespace = kubernetes_namespace.monitoring.metadata[0].name
        labels = {
          release = "${var.client_name}-prometheus"
        }
        interval = "15s"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack,
    aws_iam_role.loki
  ]
}
