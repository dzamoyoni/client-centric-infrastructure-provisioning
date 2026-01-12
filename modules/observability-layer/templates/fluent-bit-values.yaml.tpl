# Fluent Bit Helm Chart Values for Multi-Tenant Observability
# Optimized for performance and minimal storage footprint

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

resources:
  limits:
    cpu: ${resources.limits.cpu}
    memory: ${resources.limits.memory}
  requests:
    cpu: ${resources.requests.cpu}
    memory: ${resources.requests.memory}

nodeSelector:
  kubernetes.io/os: linux

tolerations:
  - key: node.kubernetes.io/not-ready
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 30
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 30

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
        storage.max_chunks_up 128

  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        multiline.parser  docker, cri
        Tag               kube.*
        Refresh_Interval  5
        Mem_Buf_Limit     50MB
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
        Exclude log ^\s*$

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
        total_file_size             50M
        upload_timeout              10m
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

# Additional labels for better tenant isolation
podLabels:
  app: fluent-bit
  component: logging
  layer: observability
  cluster: ${cluster_name}
  region: ${region}

# Pod disruption budget for better availability
podDisruptionBudget:
  enabled: false

# Service monitor for Prometheus scraping
serviceMonitor:
  enabled: true
  namespace: istio-system
  interval: 30s
  scrapeTimeout: 10s
  labels:
    release: prometheus
