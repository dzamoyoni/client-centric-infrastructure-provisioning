# Grafana Tempo Helm Chart Values for Multi-Tenant Observability
# Configured with S3 backend for scalable trace storage

tempo:
  repository: grafana/tempo
  tag: "2.3.1"
  pullPolicy: IfNotPresent

serviceAccount:
  create: false
  name: "${service_account_name}"

# Tempo configuration with S3 backend
config: |
  server:
    http_listen_port: 3100
    grpc_listen_port: 9095
    log_level: info

  distributor:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          grpc:
            endpoint: 0.0.0.0:14250
          thrift_binary:
            endpoint: 0.0.0.0:6832
          thrift_compact:
            endpoint: 0.0.0.0:6831
          thrift_http:
            endpoint: 0.0.0.0:14268

  ingester:
    max_block_duration: 5m

  compactor:
    compaction:
      block_retention: 1h

  storage:
    trace:
      backend: s3
      s3:
        bucket: ${s3_bucket_name}
        endpoint: s3.${region}.amazonaws.com
        region: ${region}
        # Use IRSA for authentication - no need for access keys
      pool:
        max_workers: 100
        queue_depth: 10000

  query_frontend:
    search:
      duration_slo: 5s
      throughput_bytes_slo: 1.073741824e+09
    trace_by_id:
      duration_slo: 5s

  metrics_generator:
    registry:
      external_labels:
        cluster: ${cluster_name}
        region: ${region}
    storage:
      path: /var/tempo/metrics
      remote_write_flush_deadline: 1m
    traces_storage:
      path: /var/tempo/metrics

# Resource configuration
resources:
  limits:
    cpu: ${resources.limits.cpu}
    memory: ${resources.limits.memory}
  requests:
    cpu: ${resources.requests.cpu}
    memory: ${resources.requests.memory}

# Persistence configuration
persistence:
  enabled: true
  size: 10Gi
  storageClassName: gp2
  accessModes:
    - ReadWriteOnce

# Service configuration for multi-protocol support
service:
  type: ClusterIP
  ports:
    - name: tempo-prom-metrics
      port: 3100
      targetPort: 3100
    - name: tempo-query
      port: 3200
      targetPort: 3100
    - name: tempo-distributor-otlp-grpc
      port: 4317
      targetPort: 4317
    - name: tempo-distributor-otlp-http
      port: 4318
      targetPort: 4318
    - name: tempo-distributor-jaeger-grpc
      port: 14250
      targetPort: 14250
    - name: tempo-distributor-jaeger-thrift-http
      port: 14268
      targetPort: 14268
    - name: tempo-distributor-jaeger-thrift-compact
      port: 6831
      targetPort: 6831
      protocol: UDP
    - name: tempo-distributor-jaeger-thrift-binary
      port: 6832
      targetPort: 6832
      protocol: UDP

# Security context
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  fsGroup: 65534
  runAsGroup: 65534

podSecurityContext:
  fsGroup: 65534

# Node selector and tolerations
nodeSelector:
  kubernetes.io/os: linux

tolerations: []

affinity: {}

# Pod labels for better identification
podLabels:
  app: tempo
  component: tracing
  layer: observability
  cluster: ${cluster_name}
  region: ${region}

# Environment variables
env:
  - name: CLUSTER_NAME
    value: ${cluster_name}
  - name: REGION
    value: ${region}

# Service monitor for Prometheus scraping
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
  labels:
    release: prometheus

# Readiness and liveness probes
readinessProbe:
  httpGet:
    path: /ready
    port: 3100
  initialDelaySeconds: 30
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /ready
    port: 3100
  initialDelaySeconds: 60
  periodSeconds: 30

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Horizontal Pod Autoscaler
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
