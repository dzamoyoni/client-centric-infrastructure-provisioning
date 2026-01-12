# Enhanced Fluent Bit Helm Chart Values for Multi-Tenant Observability
# Optimized for proper scheduling and DaemonSet priority

image:
  repository: fluent/fluent-bit
  tag: "${image_tag}"
  pullPolicy: Always

serviceAccount:
  create: false
  name: "${service_account_name}"

podSecurityContext:
  fsGroup: 65534

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 65534
  capabilities:
    drop:
    - ALL

# Production-optimized resource configuration for busy cluster
resources:
  limits:
    cpu: ${resources.limits.cpu}
    memory: ${resources.limits.memory}
  requests:
    cpu: ${resources.requests.cpu}   # Production-grade for busy cluster
    memory: ${resources.requests.memory} # Adequate for log processing

# Priority class for system DaemonSets - CRITICAL
priorityClassName: system-node-critical  # Higher priority than system-cluster-critical

nodeSelector:
  kubernetes.io/os: linux

# Enhanced tolerations for system workloads
tolerations:
  - key: node.kubernetes.io/not-ready
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 30
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 30
  - key: node.kubernetes.io/disk-pressure
    operator: Exists
    effect: NoSchedule
  - key: node.kubernetes.io/memory-pressure
    operator: Exists
    effect: NoSchedule
  - key: node.kubernetes.io/pid-pressure
    operator: Exists
    effect: NoSchedule
  - key: node.kubernetes.io/unschedulable
    operator: Exists
    effect: NoSchedule
  # Allow scheduling on all nodes including system nodes
  - key: CriticalAddonsOnly
    operator: Exists
    effect: NoSchedule

# Node affinity to ensure even distribution across nodes
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/os
          operator: In
          values:
          - linux
        - key: kubernetes.io/arch
          operator: In
          values:
          - amd64
          - arm64

daemonSetVolumes:
  - name: varlog
    hostPath:
      path: /var/log
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers
  - name: etcmachineid
    hostPath:
      path: /etc/machine-id
      type: File
  - name: fluent-bit-storage
    emptyDir: {}

daemonSetVolumeMounts:
  - name: varlog
    mountPath: /var/log
    readOnly: true
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true
  - name: etcmachineid
    mountPath: /etc/machine-id
    readOnly: true
  - name: fluent-bit-storage
    mountPath: /tmp/fluent-bit

# Rolling update strategy for minimal disruption
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1

config:
  service: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020
        Health_Check  On
        storage.path  /tmp/fluent-bit/storage
        storage.sync  normal
        storage.checksum off
        storage.max_chunks_up 64  # Reduced from 128 to use less memory

  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        multiline.parser  docker, cri
        Tag               kube.*
        Refresh_Interval  10  # Increased to reduce CPU usage
        Mem_Buf_Limit     25MB  # Reduced from 50MB
        Skip_Long_Lines   On
        Skip_Empty_Lines  On
        storage.type      filesystem
        DB                /tmp/fluent-bit/tail_db

  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Kube_Tag_Prefix     kube.var.log.containers.
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off
        Annotations         Off
        Labels              On

    [FILTER]
        Name    grep
        Match   kube.*
        Exclude log ^\\s*$

    [FILTER]
        Name          record_modifier
        Match         *
        Record        cluster_name ${cluster_name}
        Record        region ${region}

  outputs: |
    [OUTPUT]
        Name                         s3
        Match                        *
        bucket                       ${s3_bucket_name}
        region                       ${region}
        total_file_size             25M  # Reduced from 50M
        upload_timeout              5m   # Reduced from 10m
        use_put_object              On
        s3_key_format               /logs/cluster=${cluster_name}/year=%Y/month=%m/day=%d/hour=%H/%Y%m%d-%H%M%S-$UUID.gz
        s3_key_format_tag_delimiters .-
        auto_retry_requests         true
        storage_class               STANDARD_IA

  parsers: |
    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
        Time_Keep   On

    [PARSER]
        Name    cri
        Format  regex
        Regex   ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<message>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z

# Environment variables for AWS authentication (handled via IRSA)
env: []

# Additional labels for better tenant isolation and priority indication
podLabels:
  app: fluent-bit
  component: logging
  layer: observability
  cluster: ${cluster_name}
  region: ${region}
  priority: system-critical

# Pod disruption budget - allow 1 unavailable since it's a DaemonSet
podDisruptionBudget:
  enabled: true
  minAvailable: "0"  # Allow all pods to be unavailable for DaemonSet updates

# Service monitor for Prometheus scraping
serviceMonitor:
  enabled: true
  namespace: istio-system
  interval: 30s
  scrapeTimeout: 10s
  labels:
    release: prometheus

# Liveness and readiness probes with conservative settings
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 60  # Increased delay
  periodSeconds: 30       # Less frequent checks
  timeoutSeconds: 10
  failureThreshold: 5     # More tolerant

readinessProbe:
  httpGet:
    path: /api/v1/health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
