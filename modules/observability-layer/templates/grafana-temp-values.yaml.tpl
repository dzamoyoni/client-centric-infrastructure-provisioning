# Temporary Grafana Configuration for Testing
# Lightweight setup without persistent storage or external downloads

# Authentication and security
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user  
  passwordKey: admin-password

# Use emptyDir instead of persistent storage for temporary testing
persistence:
  enabled: false

# Lightweight resource configuration for testing
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 200m
    memory: 512Mi

# Security context
securityContext:
  runAsUser: 472
  runAsGroup: 472
  fsGroup: 472

# Service configuration
service:
  type: ClusterIP
  port: 80

# Ingress disabled for security
ingress:
  enabled: false

# Basic Grafana configuration
grafana.ini:
  server:
    domain: ${cluster_name}.local
    root_url: http://grafana.istio-system.svc.cluster.local
  security:
    admin_user: admin
  auth:
    disable_login_form: false
  auth.anonymous:
    enabled: false
  analytics:
    reporting_enabled: false
    check_for_updates: false
  log:
    mode: console
    level: info

# Data sources for testing
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-kube-prometheus-prometheus.istio-system.svc.cluster.local:9090
      access: proxy
      isDefault: true
      editable: true
      jsonData:
        timeInterval: 15s
    - name: Tempo
      type: tempo
      url: http://tempo.istio-system.svc.cluster.local:3100
      access: proxy
      editable: true

# Disable dashboard downloads completely
dashboards: {}
dashboardProviders: {}

# Minimal plugins for testing
plugins: []

# Environment variables
env:
  GF_EXPLORE_ENABLED: true
  GF_PANELS_DISABLE_SANITIZE_HTML: true

# No service monitor for temporary setup
serviceMonitor:
  enabled: false

# Pod labels
podLabels:
  app: grafana-temp
  component: visualization-temp
  layer: observability
  cluster: ${cluster_name}
  region: ${region}

# Fast startup probes for testing
readinessProbe:
  httpGet:
    path: /api/health
    port: 3000
  initialDelaySeconds: 10
  timeoutSeconds: 10
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /api/health
    port: 3000
  initialDelaySeconds: 30
  timeoutSeconds: 10
  periodSeconds: 30

# Node selector
nodeSelector:
  kubernetes.io/os: linux

tolerations: []
affinity: {}

# RBAC
rbac:
  create: true

serviceAccount:
  create: true
  name: grafana-temp
