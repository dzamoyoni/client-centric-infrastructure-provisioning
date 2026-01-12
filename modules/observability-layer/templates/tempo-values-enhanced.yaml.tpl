# Grafana Tempo Helm Values - Enhanced with Structured S3 Keys
# This configuration uses hierarchical S3 key patterns for better organization
# and query performance of distributed tracing data

serviceAccount:
  create: false
  name: ${service_account_name}

tempo:
  repository: grafana/tempo
  tag: "2.3.1"
  pullPolicy: IfNotPresent

  # Enhanced configuration for S3 backend with structured keys
  config: |
    server:
      http_listen_port: 3100
      
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
            thrift_http:
              endpoint: 0.0.0.0:14268

    ingester:
      trace_idle_period: 10s
      max_block_bytes: 1_000_000
      max_block_duration: 5m

    compactor:
      compaction:
        compaction_window: 1h
        max_block_bytes: 100_000_000
        block_retention: 168h  # 7 days
        compacted_block_retention: 1h

    storage:
      trace:
        backend: s3
        s3:
          bucket: ${s3_bucket_name}
          region: ${region}
          # Hierarchical key structure for traces
          # Format: traces/cluster=<cluster>/tenant=<tenant>/service=<service>/year=YYYY/month=MM/day=DD/hour=HH/
          prefix: traces/cluster=${cluster_name}
          # Use structured paths for better partitioning and query performance
          # This enables:
          # - Efficient time-based queries
          # - Tenant isolation for multi-tenant clusters  
          # - Service-level trace organization
          # - Cost optimization through lifecycle policies
          object_prefix_template: "tenant=$${tenant}/service=$${service}/year=%Y/month=%m/day=%d/hour=%H/tempo-traces-%Y%m%d-%H%M%S-$${trace_id}.gz"
          
    query_frontend:
      search:
        max_duration: 168h  # 7 days
        
    overrides:
      defaults:
        # Configure per-tenant limits
        max_traces_per_user: 10000
        max_bytes_per_trace: 5000000  # 5MB
        
      # Per-tenant overrides for multi-tenant setup
      per_tenant_override_config: |
        overrides:
          # MTN Ghana tenant configuration
          "mtn-ghana":
            max_traces_per_user: 20000
            max_bytes_per_trace: 10000000  # 10MB
            retention_period: 336h  # 14 days
            
          # Orange Madagascar tenant configuration  
          "orange-madagascar":
            max_traces_per_user: 15000
            max_bytes_per_trace: 8000000   # 8MB
            retention_period: 240h  # 10 days
            
          # Ezra Fintech tenant configuration
          "ezra-fintech":
            max_traces_per_user: 25000
            max_bytes_per_trace: 12000000  # 12MB
            retention_period: 720h  # 30 days

# Resource configuration
resources:
  limits:
    cpu: ${resources.limits.cpu}
    memory: ${resources.limits.memory}
  requests:
    cpu: ${resources.requests.cpu}
    memory: ${resources.requests.memory}

# Pod security context
securityContext:
  fsGroup: 10001
  runAsGroup: 10001
  runAsNonRoot: true
  runAsUser: 10001

# Container security context
containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true

# Persistence for temporary storage
persistence:
  enabled: true
  accessModes:
    - ReadWriteOnce
  size: 10Gi
  storageClassName: gp3

# Service configuration
service:
  type: ClusterIP
  port: 3100

# Ingress configuration (disabled by default)
ingress:
  enabled: false

# Monitoring configuration
serviceMonitor:
  enabled: true
  interval: 30s
  additionalLabels:
    app: tempo
    monitoring: prometheus

# Node selector for dedicated nodes if needed
nodeSelector: {}

# Tolerations for dedicated nodes if needed
tolerations: []

# Pod anti-affinity for high availability
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - tempo
          topologyKey: kubernetes.io/hostname

# Additional labels for all resources
commonLabels:
  cluster: ${cluster_name}
  region: ${region}
  component: distributed-tracing
  architecture: multi-tenant

# Annotations for all pods
podAnnotations:
  cluster: ${cluster_name}
  region: ${region}
  structured-logging: "enabled"
  s3-key-format: "hierarchical"