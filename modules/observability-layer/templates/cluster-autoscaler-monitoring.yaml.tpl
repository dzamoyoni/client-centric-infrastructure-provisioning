apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-autoscaler-daemonset-monitoring
  namespace: ${monitoring_namespace}
  labels:
    app: cluster-autoscaler
    component: monitoring
    managed-by: terraform
spec:
  groups:
  - name: cluster-autoscaler.rules
    rules:
    # Alert when DaemonSet pods are pending for too long
    - alert: DaemonSetPodsPending
      expr: |
        kube_pod_info{created_by_kind="DaemonSet"} * on(pod, namespace) 
        kube_pod_status_phase{phase="Pending"} > 0
      for: 5m
      labels:
        severity: warning
        component: cluster-autoscaler
      annotations:
        summary: "DaemonSet pods are stuck in Pending state"
        description: |
          DaemonSet pod {{ $labels.pod }} in namespace {{ $labels.namespace }} 
          has been in Pending state for more than 5 minutes.
          This indicates potential cluster-autoscaler configuration issues.
        runbook_url: "https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-the-parameters-to-ca"

    # Alert when Fluent Bit specifically is not scheduled
    - alert: FluentBitPodsUnschedulable
      expr: |
        kube_pod_info{pod=~"fluent-bit-.*"} * on(pod, namespace) 
        kube_pod_status_phase{phase="Pending"} > 0
      for: 2m
      labels:
        severity: critical
        component: fluent-bit
      annotations:
        summary: "Fluent Bit DaemonSet pods cannot be scheduled"
        description: |
          Fluent Bit pod {{ $labels.pod }} cannot be scheduled on any node.
          This will affect log collection across the cluster.
          Check node resources and cluster-autoscaler configuration.
        runbook_url: "https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/#scheduled-by-default-scheduler"

    # Alert on high node CPU utilization that might prevent DaemonSet scheduling
    - alert: NodeCPUUtilizationHigh
      expr: |
        (
          (1 - rate(node_cpu_seconds_total{mode="idle"}[5m]))
          * on(instance) group_left(node)
          node_uname_info
        ) > 0.95
      for: 5m
      labels:
        severity: warning
        component: cluster-resources
      annotations:
        summary: "Node CPU utilization is very high"
        description: |
          Node {{ $labels.node }} has CPU utilization above 95% for more than 5 minutes.
          This may prevent DaemonSet pods from being scheduled.
        runbook_url: "https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"

    # Alert when cluster-autoscaler is not scaling up despite unschedulable pods
    - alert: ClusterAutoscalerNotScaling
      expr: |
        increase(cluster_autoscaler_unschedulable_pods_count[10m]) > 0
        and
        increase(cluster_autoscaler_cluster_safe_to_autoscale[10m]) == 0
      for: 15m
      labels:
        severity: critical
        component: cluster-autoscaler
      annotations:
        summary: "Cluster Autoscaler is not scaling despite unschedulable pods"
        description: |
          Cluster Autoscaler has detected unschedulable pods but hasn't scaled up for 15 minutes.
          This indicates a configuration issue with the autoscaler.
        runbook_url: "https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-does-scale-up-work"

    # Alert on cluster-autoscaler errors
    - alert: ClusterAutoscalerErrors
      expr: |
        increase(cluster_autoscaler_errors_total[5m]) > 0
      for: 1m
      labels:
        severity: warning
        component: cluster-autoscaler
      annotations:
        summary: "Cluster Autoscaler is experiencing errors"
        description: |
          Cluster Autoscaler has encountered {{ $value }} errors in the last 5 minutes.
          Error type: {{ $labels.type }}
        runbook_url: "https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-the-common-errors"

    # Alert when node groups are at maximum capacity
    - alert: NodeGroupAtMaxCapacity
      expr: |
        cluster_autoscaler_node_group_size >= cluster_autoscaler_node_group_max_size
      for: 5m
      labels:
        severity: warning
        component: cluster-autoscaler
      annotations:
        summary: "Node group has reached maximum capacity"
        description: |
          Node group {{ $labels.node_group }} has reached its maximum size of {{ $value }} nodes.
          Consider increasing the maximum size if more capacity is needed.
        runbook_url: "https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html"

  - name: daemonset.rules
    rules:
    # Rule to track DaemonSet pod distribution
    - record: daemonset:pods_not_ready:ratio
      expr: |
        (
          kube_daemonset_status_number_unavailable
          /
          kube_daemonset_status_desired_number_scheduled
        ) or vector(0)

    # Rule to track node resource pressure
    - record: node:resource_pressure:ratio
      expr: |
        (
          (kube_node_status_allocatable{resource="cpu"} - kube_node_status_capacity{resource="cpu"})
          /
          kube_node_status_capacity{resource="cpu"}
        )

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cluster-autoscaler-metrics
  namespace: ${monitoring_namespace}
  labels:
    app: cluster-autoscaler
    component: monitoring
    managed-by: terraform
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: aws-cluster-autoscaler
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
    scrapeTimeout: 10s
  namespaceSelector:
    matchNames:
    - kube-system
