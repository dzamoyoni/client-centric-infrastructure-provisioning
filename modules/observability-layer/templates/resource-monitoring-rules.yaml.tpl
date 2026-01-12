# Enhanced Resource Monitoring and Pod Scheduling Alert Rules
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: resource-monitoring-alerts
  namespace: ${monitoring_namespace}
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/part-of: kube-prometheus-stack
spec:
  groups:
  - name: resource.exhaustion
    rules:
    # Alert when Prometheus pod is pending
    - alert: PrometheusServerPending
      expr: kube_pod_status_phase{pod=~"prometheus-.*", phase="Pending"} == 1
      for: 2m
      labels:
        severity: critical
        component: prometheus
      annotations:
        summary: "Prometheus server pod is pending"
        description: "Prometheus server pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been in Pending state for more than 2 minutes."
        
    # Alert when any critical monitoring pod is pending
    - alert: CriticalMonitoringPodPending
      expr: kube_pod_status_phase{pod=~"(prometheus|grafana|alertmanager|tempo).*", phase="Pending"} == 1
      for: 1m
      labels:
        severity: warning
        component: monitoring
      annotations:
        summary: "Critical monitoring pod is pending"
        description: "Critical monitoring pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been in Pending state for more than 1 minute."
    
    # Alert when DaemonSet pods are pending (like Fluent Bit)
    - alert: DaemonSetPodPending
      expr: kube_pod_status_phase{pod=~"fluent-bit.*", phase="Pending"} == 1
      for: 30s
      labels:
        severity: critical
        component: logging
      annotations:
        summary: "DaemonSet pod is pending - cluster autoscaling issue"
        description: "DaemonSet pod {{ $labels.pod }} is pending, likely due to cluster-autoscaler not recognizing DaemonSet scheduling requirements."
    
    # Alert on high CPU requests across cluster
    - alert: ClusterCPURequestsHigh
      expr: (sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"})) * 100 > 80
      for: 5m
      labels:
        severity: warning
        component: cluster
      annotations:
        summary: "Cluster CPU requests are high"
        description: "Cluster CPU requests are at {{ $value | humanizePercentage }} of total allocatable CPU."
        
    # Alert on high memory requests across cluster
    - alert: ClusterMemoryRequestsHigh
      expr: (sum(kube_pod_container_resource_requests{resource="memory"}) / sum(kube_node_status_allocatable{resource="memory"})) * 100 > 80
      for: 5m
      labels:
        severity: warning
        component: cluster
      annotations:
        summary: "Cluster memory requests are high"
        description: "Cluster memory requests are at {{ $value | humanizePercentage }} of total allocatable memory."
        
    # Alert on node resource pressure
    - alert: NodeUnderResourcePressure
      expr: kube_node_status_condition{condition=~"MemoryPressure|DiskPressure", status="true"} == 1
      for: 2m
      labels:
        severity: critical
        component: node
      annotations:
        summary: "Node is under resource pressure"
        description: "Node {{ $labels.node }} is experiencing {{ $labels.condition }}."
        
    # Alert when cluster autoscaler is not working properly
    - alert: ClusterAutoscalerErrors
      expr: increase(cluster_autoscaler_errors_total[5m]) > 3
      for: 2m
      labels:
        severity: warning
        component: autoscaler
      annotations:
        summary: "Cluster autoscaler experiencing errors"
        description: "Cluster autoscaler has experienced {{ $value }} errors in the last 5 minutes."

  - name: prometheus.health
    rules:
    # Alert when Prometheus target is down
    - alert: PrometheusTargetDown
      expr: up{job=~"prometheus.*"} == 0
      for: 1m
      labels:
        severity: critical
        component: prometheus
      annotations:
        summary: "Prometheus target is down"
        description: "Prometheus target {{ $labels.instance }} has been down for more than 1 minute."
        
    # Alert when Prometheus is consuming too much memory
    - alert: PrometheusHighMemoryUsage
      expr: (process_resident_memory_bytes{job=~"prometheus.*"} / 1024 / 1024) > 3000
      for: 5m
      labels:
        severity: warning
        component: prometheus
      annotations:
        summary: "Prometheus memory usage is high"
        description: "Prometheus instance {{ $labels.instance }} is using {{ $value }}MB of memory."
        
    # Alert when Prometheus ingestion rate is too high
    - alert: PrometheusHighIngestionRate
      expr: rate(prometheus_tsdb_samples_appended_total[5m]) > 50000
      for: 2m
      labels:
        severity: warning
        component: prometheus
      annotations:
        summary: "Prometheus ingestion rate is high"
        description: "Prometheus instance {{ $labels.instance }} ingestion rate is {{ $value }} samples/sec."

  - name: pod.resources
    rules:
    # Alert when pods are getting OOMKilled
    - alert: PodOOMKilled
      expr: increase(kube_pod_container_status_restarts_total{reason="OOMKilled"}[5m]) > 0
      for: 0m
      labels:
        severity: warning
        component: pod
      annotations:
        summary: "Pod was OOMKilled"
        description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} was OOMKilled."
        
    # Alert when pods are CPU throttled
    - alert: PodCPUThrottled
      expr: (rate(container_cpu_cfs_throttled_seconds_total[5m]) / rate(container_cpu_cfs_periods_total[5m])) > 0.8
      for: 5m
      labels:
        severity: warning
        component: pod
      annotations:
        summary: "Pod CPU is being throttled"
        description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is being CPU throttled {{ $value | humanizePercentage }} of the time."
