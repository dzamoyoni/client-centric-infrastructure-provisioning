# Prometheus Helm Chart Values for Multi-Tenant Observability
# Configured with remote write to central Grafana

prometheus:
  prometheusSpec:
    # Priority class for critical infrastructure scheduling
    priorityClassName: system-cluster-critical
    
    # Resource configuration - production optimized for busy clusters
    resources:
      requests:
        cpu: ${resources.requests.cpu}
        memory: ${resources.requests.memory}
      limits:
        cpu: ${resources.limits.cpu}
        memory: ${resources.limits.memory}
    
    # Node affinity for better scheduling
    affinity:
      nodeAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
            - key: node.kubernetes.io/instance-type
              operator: NotIn
              values: ["t3.micro", "t3.small"]
    
    # Tolerations for dedicated nodes if needed
    tolerations:
    - key: "CriticalAddonsOnly"
      operator: "Exists"
    - key: "node-role.kubernetes.io/master"
      operator: "Exists"
      effect: "NoSchedule"

    # Storage configuration
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${storage_size}

    # Remote write configuration to central Grafana
    remoteWrite:
    %{ if remote_write_url != "" && remote_write_password != "disabled" }
    - url: ${remote_write_url}
      basicAuth:
        username:
          name: prometheus-remote-write-auth
          key: username
        password:
          name: prometheus-remote-write-auth
          key: password
      writeRelabelConfigs:
      - sourceLabels: [__name__]
        regex: 'istio_.*|up|prometheus_.*'
        action: keep
      - sourceLabels: [cluster]
        targetLabel: cluster
        replacement: ${cluster_name}
      - sourceLabels: [region]
        targetLabel: region
        replacement: ${region}
      queueConfig:
        maxSamplesPerSend: 1000
        maxShards: 200
        capacity: 2500
    %{ endif }

    # External labels for multi-cluster identification
    externalLabels:
      cluster: ${cluster_name}
      region: ${region}
      environment: production

    # Service discovery and scraping configuration
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    
    # Retention configuration
    retention: "15d"
    retentionSize: "10GB"

    # Security context
    securityContext:
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534

    # Additional scrape configs for Istio
    additionalScrapeConfigs:
    - job_name: 'istio-mesh'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - istio-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: istio-proxy;http-monitoring
      - source_labels: [__address__, __meta_kubernetes_endpoint_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: service_name

    - job_name: 'istio-policy'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - istio-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: istio-policy;http-policy-monitoring
      - source_labels: [__address__, __meta_kubernetes_endpoint_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__

    - job_name: 'istio-telemetry'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - istio-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: istio-telemetry;http-telemetry-monitoring
      - source_labels: [__address__, __meta_kubernetes_endpoint_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__

    - job_name: 'pilot'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - istio-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: istiod;http-monitoring
      - source_labels: [__address__, __meta_kubernetes_endpoint_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__

# Grafana configuration
grafana:
  enabled: false  # We'll use separate Grafana deployment

# AlertManager configuration  
alertmanager:
  enabled: %{ if enable_alertmanager }true%{ else }false%{ endif }

# Node exporter for node metrics
nodeExporter:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 100m
      memory: 100Mi

# Kube-state-metrics for cluster state
kubeStateMetrics:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 150Mi
    limits:
      cpu: 100m
      memory: 300Mi

# Prometheus operator configuration
prometheusOperator:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 200m  
      memory: 200Mi

# Additional labels for tenant identification
commonLabels:
  cluster: ${cluster_name}
  region: ${region}
  layer: observability
