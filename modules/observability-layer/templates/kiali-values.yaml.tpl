# Kiali Helm Chart Values for Service Mesh Visualization
# Multi-tenant configuration with Istio integration

auth:
  strategy: ${auth_strategy}

external_services:
  prometheus:
    url: "${prometheus_url}"
  grafana:
    enabled: false  # Using external central Grafana
  jaeger:
    enabled: false  # Using Tempo instead
  tracing:
    enabled: true
    in_cluster_url: "http://tempo.istio-system.svc.cluster.local:3100"
    use_grpc: true
    url: "http://tempo.istio-system.svc.cluster.local:16686"

istio_namespace: "istio-system"

deployment:
  ingress_enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 1Gi

  # Security context
  security_context:
    run_as_non_root: true
    run_as_user: 1001
    run_as_group: 1001

server:
  port: 20001
  metrics_enabled: true
  metrics_port: 9090
  web_root: "/"

# Kiali configuration
kiali_feature_flags:
  certificates_information_indicators:
    enabled: true
    secrets:
    - cacerts
    - istio-ca-secret
  clustering:
    enabled: false
  disabled_features: []
  validations:
    ignore: ["KIA1301"]

# Login token signing key (32 bytes)
login_token:
  signing_key: "12345678901234567890123456789012"

# Service mesh configuration
mesh_tls:
  enabled: true

# Multi-cluster configuration
additional_display_details:
- title: "Cluster"
  annotation: "kiali.io/cluster"
- title: "Region" 
  annotation: "kiali.io/region"

# Custom labels for tenant identification
custom_labels:
  cluster: ${cluster_name}
  region: ${region}
  layer: observability

# Health configuration for multi-tenant environments
health_config:
  rate:
  - namespace: ".*"
    kind: ".*"
    name: ".*"
    tolerance:
    - protocol: "http"
      direction: ".*"
      code: "[1-9]\\d\\d"
      degraded: 5
      failure: 10

# Namespace management for multi-tenancy
api:
  namespaces:
    exclude:
    - "kube-.*"
    - "openshift.*"
    include: []

# Performance and resource optimization
performance:
  batch_size: 100
  concurrent_requests: 10
