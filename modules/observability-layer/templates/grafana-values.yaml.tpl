# Grafana Helm Chart Values for Production Observability
# Configured with Istio dashboards and production features

# Authentication and security
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user
  passwordKey: admin-password

# Persistence configuration
persistence:
  enabled: true
  type: pvc
  storageClassName: gp2
  accessModes:
    - ReadWriteOnce
  size: ${storage_size}

# Resource configuration
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi

# Security context
securityContext:
  runAsUser: 472
  runAsGroup: 472
  fsGroup: 472

# Service configuration
service:
  type: ClusterIP
  port: 80

# Ingress (disabled for production security)
ingress:
  enabled: false

# Grafana configuration
grafana.ini:
  server:
    domain: ${cluster_name}.local
    root_url: http://grafana.istio-system.svc.cluster.local
  security:
    admin_user: admin
    cookie_secure: true
    cookie_samesite: strict
  auth:
    disable_login_form: false
    disable_signout_menu: false
  auth.anonymous:
    enabled: false
  analytics:
    reporting_enabled: false
    check_for_updates: false
  log:
    mode: console
    level: info

# Data sources configuration
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
        timeInterval: 5s
    - name: Tempo
      type: tempo
      url: http://tempo.istio-system.svc.cluster.local:3100
      access: proxy
      editable: true
      jsonData:
        httpMethod: GET
        serviceMap:
          datasourceUid: prometheus-uid

# Dashboard providers
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'istio'
      orgId: 1
      folder: 'Istio Service Mesh'
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/istio
    - name: 'kubernetes'
      orgId: 1
      folder: 'Kubernetes'
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/kubernetes
    - name: 'infrastructure'
      orgId: 1
      folder: 'Infrastructure'
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/infrastructure

# Dashboard downloads disabled to prevent init container failures
# Dashboards can be manually imported later or provided as ConfigMaps
dashboards: {}

# Plugin configuration
plugins:
  - grafana-piechart-panel
  - grafana-worldmap-panel
  - grafana-clock-panel
  - grafana-simple-json-datasource

# Environment variables
env:
  GF_EXPLORE_ENABLED: true
  GF_PANELS_DISABLE_SANITIZE_HTML: true
  GF_LOG_FILTERS: rendering:debug
  GF_DATE_FORMATS_USE_BROWSER_LOCALE: true

# Service monitor for Prometheus scraping
serviceMonitor:
  enabled: true
  interval: 30s
  scrapeTimeout: 10s
  labels:
    release: prometheus

# Pod labels
podLabels:
  app: grafana
  component: visualization
  layer: observability
  cluster: ${cluster_name}
  region: ${region}

# Pod annotations
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "3000"
  prometheus.io/path: "/metrics"

# Readiness and liveness probes
readinessProbe:
  httpGet:
    path: /robots.txt
    port: 3000
  initialDelaySeconds: 60
  timeoutSeconds: 30
  failureThreshold: 3
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /robots.txt
    port: 3000
  initialDelaySeconds: 60
  timeoutSeconds: 30
  failureThreshold: 3
  periodSeconds: 10

# Node selector and tolerations
nodeSelector:
  kubernetes.io/os: linux

tolerations: []

affinity: {}

# RBAC
rbac:
  create: true

serviceAccount:
  create: true
  name: grafana
