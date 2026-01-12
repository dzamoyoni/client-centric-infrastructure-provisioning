# =============================================================================
# Fluent Bit - Log Collection DaemonSet
# =============================================================================
# Fluent Bit DaemonSet that runs on ALL nodes to collect logs
# Outputs: Loki (real-time) and S3 (long-term storage)
# =============================================================================

resource "helm_release" "fluent_bit" {
  count      = var.enable_fluent_bit ? 1 : 0
  name       = "${var.client_name}-fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = "0.46.7"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600
  wait       = true

  values = [
    yamlencode({
      # ==========================================================================
      # DaemonSet Configuration - Runs on ALL nodes
      # ==========================================================================
      kind = "DaemonSet"

      # Tolerations to run on ALL nodes
      tolerations = [{
        operator = "Exists"
        effect   = ""
      }]

      # Resource limits - lightweight for DaemonSet
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

      # ==========================================================================
      # Service Account with IRSA
      # ==========================================================================
      serviceAccount = {
        create = true
        name   = "fluent-bit"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.fluent_bit.arn
        }
      }

      # ==========================================================================
      # Fluent Bit Configuration
      # ==========================================================================
      config = {
        service = <<-EOT
          [SERVICE]
              Daemon Off
              Flush 1
              Log_Level info
              Parsers_File parsers.conf
              Parsers_File custom_parsers.conf
              HTTP_Server On
              HTTP_Listen 0.0.0.0
              HTTP_Port 2020
              Health_Check On
        EOT

        inputs = <<-EOT
          [INPUT]
              Name tail
              Path /var/log/containers/*.log
              multiline.parser docker, cri
              Tag kube.*
              Mem_Buf_Limit 5MB
              Skip_Long_Lines On
              Refresh_Interval 10
        EOT

        filters = <<-EOT
          [FILTER]
              Name kubernetes
              Match kube.*
              Kube_URL https://kubernetes.default.svc:443
              Kube_CA_File /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              Kube_Token_File /var/run/secrets/kubernetes.io/serviceaccount/token
              Kube_Tag_Prefix kube.var.log.containers.
              Merge_Log On
              Keep_Log Off
              K8S-Logging.Parser On
              K8S-Logging.Exclude On
              Labels On
              Annotations Off

          [FILTER]
              Name modify
              Match kube.*
              Add client ${var.client_name}
              Add tier ${var.client_tier}
              Add cluster ${var.cluster_name}
              Add environment ${var.environment}
        EOT

        outputs = <<-EOT
          %{if var.enable_loki~}
          [OUTPUT]
              Name loki
              Match kube.*
              Host ${var.client_name}-loki-gateway.${local.namespace}.svc.cluster.local
              Port 80
              Labels job=fluentbit, client=${var.client_name}, tier=${var.client_tier}
              auto_kubernetes_labels on
              label_keys $$kubernetes['namespace_name'],$$kubernetes['pod_name'],$$kubernetes['container_name']
          %{~endif}

          [OUTPUT]
              Name s3
              Match kube.*
              bucket ${var.shared_logs_bucket}
              region ${var.region}
              s3_key_format /${local.logs_prefix}$$TAG[2]/$$TAG[0]/%Y/%m/%d/$$UUID.gz
              total_file_size 100M
              upload_timeout 1m
              use_put_object On
              compression gzip
              retry_limit 3
        EOT
      }

      # ==========================================================================
      # ServiceMonitor for Prometheus
      # ==========================================================================
      serviceMonitor = {
        enabled = true
        labels = {
          release = "${var.client_name}-prometheus"
        }
        interval = "30s"
      }

      # ==========================================================================
      # Pod Labels
      # ==========================================================================
      podLabels = {
        client      = var.client_name
        tier        = var.client_tier
        environment = var.environment
      }

      # ==========================================================================
      # Volume Mounts for Log Collection
      # ==========================================================================
      volumeMounts = [
        {
          name      = "varlog"
          mountPath = "/var/log"
          readOnly  = true
        },
        {
          name      = "varlibdockercontainers"
          mountPath = "/var/lib/docker/containers"
          readOnly  = true
        }
      ]

      daemonSetVolumes = [
        {
          name = "varlog"
          hostPath = {
            path = "/var/log"
          }
        },
        {
          name = "varlibdockercontainers"
          hostPath = {
            path = "/var/lib/docker/containers"
          }
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    aws_iam_role.fluent_bit,
    helm_release.prometheus_stack,
    helm_release.loki
  ]
}
