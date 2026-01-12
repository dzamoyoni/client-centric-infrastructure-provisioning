apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: enhanced-monitoring-rules
  namespace: ${monitoring_namespace}
  labels:
    app: prometheus
    component: server
spec:
  groups:
  - name: kubernetes.rules
    interval: 30s
    rules:
    # Kubernetes Node Monitoring
    - alert: KubernetesNodeReady
      expr: kube_node_status_condition{condition="Ready",status="true"} == 0
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes node not ready
        description: "Node {{ $labels.node }} has been unready for a long time"

    - alert: KubernetesMemoryPressure
      expr: kube_node_status_condition{condition="MemoryPressure",status="true"} == 1
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes memory pressure
        description: "Node {{ $labels.node }} has memory pressure"

    - alert: KubernetesPIDPressure
      expr: kube_node_status_condition{condition="PIDPressure",status="true"} == 1
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes PID pressure
        description: "Node {{ $labels.node }} has PID pressure"

    - alert: KubernetesOutOfDisk
      expr: kube_node_status_condition{condition="OutOfDisk",status="true"} == 1
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes out of disk
        description: "Node {{ $labels.node }} has disk pressure"

    - alert: KubernetesOutOfCapacity
      expr: sum by (node) ((kube_pod_status_phase{phase="Running"} == 1) + on(uid) group_left(node) (0 * kube_pod_info{pod_template_hash=""})) / sum by (node) (kube_node_status_allocatable{resource="pods"}) * 100 > 90
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Kubernetes out of capacity
        description: "Node {{ $labels.node }} is out of capacity"

  - name: kubernetes-storage
    interval: 30s
    rules:
    - alert: KubernetesPersistentvolumeclaimPending
      expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Kubernetes PersistentVolumeClaim pending
        description: "PersistentVolumeClaim {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is pending"

    - alert: KubernetesVolumeOutOfDiskSpace
      expr: kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes * 100 < 10
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Kubernetes Volume out of disk space
        description: "Volume is almost full (< 10% left)"

    - alert: KubernetesVolumeFullInFourDays
      expr: predict_linear(kubelet_volume_stats_available_bytes[6h], 4 * 24 * 3600) < 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes Volume full in four days
        description: "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is expected to fill up within four days. Currently {{ $value | humanizePercentage }} is available."

  - name: kubernetes-system
    interval: 30s
    rules:
    - alert: KubernetesStatefulsetDown
      expr: (kube_statefulset_status_replicas_ready / kube_statefulset_status_replicas_current) != 1
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: Kubernetes StatefulSet down
        description: "A StatefulSet went down"

    - alert: KubernetesHpaScalingAbility
      expr: kube_horizontalpodautoscaler_status_condition{status="false", condition="AbleToScale"} == 1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Kubernetes HPA scaling ability
        description: "Pod is unable to scale"

    - alert: KubernetesHpaMetricAvailability
      expr: kube_horizontalpodautoscaler_status_condition{status="false", condition="ScalingActive"} == 1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Kubernetes HPA metric availability
        description: "HPA is not able to collect metrics"

    - alert: KubernetesHpaScaleCapability
      expr: kube_horizontalpodautoscaler_status_desired_replicas >= kube_horizontalpodautoscaler_spec_max_replicas
      for: 2m
      labels:
        severity: info
      annotations:
        summary: Kubernetes HPA scale capability
        description: "The maximum number of desired Pods has been hit"

  - name: istio.rules
    interval: 30s
    rules:
    # Istio Service Mesh Monitoring
    - alert: IstioHighRequestLatency
      expr: histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket[1m])) by (le, source_app, destination_service_name)) > 1000
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: High request latency in Istio service mesh
        description: "Service {{ $labels.destination_service_name }} has 99th percentile latency above 1s"

    - alert: IstioHighErrorRate
      expr: sum(rate(istio_requests_total{response_code!~"2.*"}[1m])) by (source_app, destination_service_name) / sum(rate(istio_requests_total[1m])) by (source_app, destination_service_name) > 0.05
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: High error rate in Istio service mesh
        description: "Service {{ $labels.destination_service_name }} has error rate above 5%"

    - alert: IstioLowSuccessRate
      expr: sum(rate(istio_requests_total{response_code=~"2.*"}[1m])) by (source_app, destination_service_name) / sum(rate(istio_requests_total[1m])) by (source_app, destination_service_name) < 0.90
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: Low success rate in Istio service mesh
        description: "Service {{ $labels.destination_service_name }} has success rate below 90%"

%{ if enable_postgres_monitoring ~}
  - name: postgresql.rules
    interval: 30s
    rules:
    # PostgreSQL Database Monitoring
    - alert: PostgresqlDown
      expr: pg_up == 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Postgresql down
        description: "Postgresql instance is down"

    - alert: PostgresqlRestarted
      expr: time() - pg_postmaster_start_time_seconds < 60
      for: 0m
      labels:
        severity: info
      annotations:
        summary: Postgresql restarted
        description: "Postgresql restarted"

    - alert: PostgresqlExporterError
      expr: pg_exporter_last_scrape_error > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Postgresql exporter error
        description: "Postgresql exporter is showing errors. A query may be buggy in query.yaml"

    - alert: PostgresqlTooManyConnections
      expr: sum by (datname) (pg_stat_activity_count{datname!~"template.*|postgres"}) > pg_settings_max_connections * 0.8
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Postgresql too many connections
        description: "PostgreSQL instance has too many connections (> 80%)"

    - alert: PostgresqlNotEnoughConnections
      expr: sum by (datname) (pg_stat_activity_count{datname!~"template.*|postgres"}) < 1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Postgresql not enough connections
        description: "PostgreSQL instance should have more connections (> 5)"

    - alert: PostgresqlSlowQueries
      expr: pg_slow_queries > 0
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Postgresql slow queries
        description: "PostgreSQL executes slow queries"

    - alert: PostgresqlHighRollbackRate
      expr: rate(pg_stat_database_xact_rollback{datname!~"template.*"}[3m]) / rate(pg_stat_database_xact_commit{datname!~"template.*"}[3m]) > 0.02
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Postgresql high rollback rate
        description: "Ratio of transactions being aborted compared to committed is > 2 %"

    - alert: PostgresqlCommitRateLow
      expr: rate(pg_stat_database_xact_commit[1m]) < 10
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: Postgresql commit rate low
        description: "Postgresql seems to be processing very few transactions"

    - alert: PostgresqlLowXidConsumption
      expr: rate(pg_txid_current[1m]) < 5
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Postgresql low XID consumption
        description: "Postgresql seems to be consuming transaction IDs very slowly"

    - alert: PostgresqlHighConnections
      expr: sum by (datname) (pg_stat_activity_count{datname!~"template.*|postgres"}) > 200
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Postgresql high connections
        description: "Postgresql instance has too many connections"

    - alert: PostgresqlWaleReplicationStopped
      expr: rate(pg_stat_replication_pg_wal_lsn_diff[1m]) == 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Postgresql WALE replication stopped
        description: "WAL-E replication seems to be stopped"

    - alert: PostgresqlHighReplicationLag
      expr: (pg_stat_replication_pg_wal_lsn_diff > 1e+09) and ON(instance) (pg_stat_replication_pg_wal_lsn_diff - pg_stat_replication_pg_wal_lsn_diff offset 5m < 1e+06)
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Postgresql high replication lag
        description: "Postgresql replication lag is going up (> 1GB)"
%{ endif ~}

  - name: prometheus.rules
    interval: 30s
    rules:
    # Prometheus Self-Monitoring
    - alert: PrometheusJobMissing
      expr: absent(up{job="prometheus"})
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus job missing
        description: "A Prometheus job has disappeared"

    - alert: PrometheusTargetMissing
      expr: up == 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus target missing
        description: "A Prometheus target has disappeared. An exporter might be crashed."

    - alert: PrometheusAllTargetsMissing
      expr: count by (job) (up) == 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus all targets missing
        description: "A Prometheus job does not have living target anymore."

    - alert: PrometheusConfigurationReloadFailure
      expr: prometheus_config_last_reload_successful != 1
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus configuration reload failure
        description: "Prometheus configuration reload error"

    - alert: PrometheusTooManyRestarts
      expr: changes(process_start_time_seconds{job=~"prometheus|pushgateway|alertmanager"}[15m]) > 2
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus too many restarts
        description: "Prometheus has restarted more than twice in the last 15 minutes. It might be crashlooping."

    - alert: PrometheusAlertmanagerJobMissing
      expr: absent(up{job="alertmanager"})
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus AlertManager job missing
        description: "A Prometheus AlertManager job has disappeared"

    - alert: PrometheusAlertmanagerConfigurationReloadFailure
      expr: alertmanager_config_last_reload_successful != 1
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus AlertManager configuration reload failure
        description: "AlertManager configuration reload error"

    - alert: PrometheusAlertmanagerConfigNotSynced
      expr: count(count_values("config_hash", alertmanager_config_hash)) > 1
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus AlertManager config not synced
        description: "Configurations of AlertManager cluster instances are out of sync"

    - alert: PrometheusNotConnectedToAlertmanager
      expr: prometheus_notifications_alertmanagers_discovered < 1
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus not connected to alertmanager
        description: "Prometheus cannot connect the alertmanager"

    - alert: PrometheusRuleEvaluationFailures
      expr: increase(prometheus_rule_evaluation_failures_total[3m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus rule evaluation failures
        description: "Prometheus encountered {{ $value }} rule evaluation failures, leading to potentially ignored alerts."

    - alert: PrometheusTemplateTextExpansionFailures
      expr: increase(prometheus_template_text_expansion_failures_total[3m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus template text expansion failures
        description: "Prometheus encountered {{ $value }} template text expansion failures"

    - alert: PrometheusRuleEvaluationSlow
      expr: prometheus_rule_group_last_duration_seconds > prometheus_rule_group_interval_seconds
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Prometheus rule evaluation slow
        description: "Prometheus rule evaluation took more time than the scheduled interval. It indicates a slower storage backend access or too complex query."

    - alert: PrometheusNotificationsBacklog
      expr: min_over_time(prometheus_notifications_queue_length[10m]) > 0
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus notifications backlog
        description: "The Prometheus notification queue has not been empty for 10 minutes"

    - alert: PrometheusAlertmanagerNotificationFailing
      expr: rate(alertmanager_notifications_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus AlertManager notification failing
        description: "Alertmanager is failing sending notifications"

    - alert: PrometheusTargetEmpty
      expr: prometheus_sd_discovered_targets == 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus target empty
        description: "Prometheus has no target in service discovery"

    - alert: PrometheusTargetScrapingSlow
      expr: prometheus_target_interval_length_seconds{quantile="0.9"} > 60
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Prometheus target scraping slow
        description: "Prometheus is scraping exporters slowly"

    - alert: PrometheusLargeScrape
      expr: increase(prometheus_target_scrapes_exceeded_sample_limit_total[10m]) > 10
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Prometheus large scrape
        description: "Prometheus has many scrapes that exceed the sample limit"

    - alert: PrometheusTargetScrapeDuplicate
      expr: increase(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m]) > 0
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Prometheus target scrape duplicate
        description: "Prometheus has many samples rejected due to duplicate timestamps but different values"

    - alert: PrometheusTsdbCheckpointCreationFailures
      expr: increase(prometheus_tsdb_checkpoint_creations_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB checkpoint creation failures
        description: "Prometheus encountered {{ $value }} checkpoint creation failures"

    - alert: PrometheusTsdbCheckpointDeletionFailures
      expr: increase(prometheus_tsdb_checkpoint_deletions_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB checkpoint deletion failures
        description: "Prometheus encountered {{ $value }} checkpoint deletion failures"

    - alert: PrometheusTsdbCompactionsFailed
      expr: increase(prometheus_tsdb_compactions_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB compactions failed
        description: "Prometheus encountered {{ $value }} TSDB compactions failures"

    - alert: PrometheusTsdbHeadTruncationsFailed
      expr: increase(prometheus_tsdb_head_truncations_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB head truncations failed
        description: "Prometheus encountered {{ $value }} TSDB head truncation failures"

    - alert: PrometheusTsdbReloadFailures
      expr: increase(prometheus_tsdb_reloads_failures_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB reload failures
        description: "Prometheus encountered {{ $value }} TSDB reload failures"

    - alert: PrometheusTsdbWalCorruptions
      expr: increase(prometheus_tsdb_wal_corruptions_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB WAL corruptions
        description: "Prometheus encountered {{ $value }} TSDB WAL corruptions"

    - alert: PrometheusTsdbWalTruncationsFailed
      expr: increase(prometheus_tsdb_wal_truncations_failed_total[1m]) > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Prometheus TSDB WAL truncations failed
        description: "Prometheus encountered {{ $value }} TSDB WAL truncation failures"

  - name: host.rules
    interval: 30s
    rules:
    # Host and Infrastructure Monitoring
    - alert: HostOutOfMemory
      expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host out of memory
        description: "Node memory is filling up (< 10% left)"

    - alert: HostMemoryUnderMemoryPressure
      expr: rate(node_vmstat_pgmajfault[1m]) > 1000
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host memory under memory pressure
        description: "The node is under heavy memory pressure. High rate of major page faults"

    - alert: HostOutOfDiskSpace
      expr: (node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10 and ON (instance, device, mountpoint) node_filesystem_readonly == 0
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host out of disk space
        description: "Disk is almost full (< 10% left)"

    - alert: HostDiskWillFillIn24Hours
      expr: (node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10 and ON (instance, device, mountpoint) predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs"}[1h], 24*3600) < 0 and ON (instance, device, mountpoint) node_filesystem_readonly == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: Host disk will fill in 24 hours
        description: "Filesystem is predicted to run out of space within the next 24 hours at current write rate"

    - alert: HostOutOfInodes
      expr: node_filesystem_files_free{mountpoint ="/"} / node_filesystem_files{mountpoint="/"} * 100 < 10 and ON (instance, device, mountpoint) node_filesystem_readonly{mountpoint="/"} == 0
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host out of inodes
        description: "Disk is almost running out of available inodes (< 10% left)"

    - alert: HostFilesystemDeviceError
      expr: node_filesystem_device_error == 1
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Host filesystem device error
        description: "{{ $labels.instance }} device {{ $labels.device }} filesystem error"

    - alert: HostHighCpuLoad
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 80
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Host high CPU load
        description: "CPU load is > 80%"

    - alert: HostCpuStealNoisyNeighbor
      expr: avg by(instance) (rate(node_cpu_seconds_total{mode="steal"}[5m])) * 100 > 10
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Host CPU steal noisy neighbor
        description: "CPU steal is > 10%. A noisy neighbor is killing VM performances or a spot instance may be out of credit."

    - alert: HostSwapIsFillingUp
      expr: (1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 80
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host swap is filling up
        description: "Swap is filling up (>80%)"

    - alert: HostSystemdServiceCrashed
      expr: node_systemd_unit_state{state="failed"} == 1
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Host systemd service crashed
        description: "systemd service crashed"

    - alert: HostPhysicalComponentTooHot
      expr: node_hwmon_temp_celsius > 75
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Host physical component too hot
        description: "Physical hardware component too hot"

    - alert: HostNodeOvertemperatureAlarm
      expr: node_hwmon_temp_crit_alarm_celsius == 1
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Host node overtemperature alarm
        description: "Physical node temperature alarm triggered"

    - alert: HostRaidArrayGotInactive
      expr: node_md_state{state="inactive"} > 0
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: Host RAID array got inactive
        description: "RAID array {{ $labels.device }} is in degraded state due to one or more disks failures. Number of spare drives is insufficient to fix issue automatically."

    - alert: HostRaidDiskFailure
      expr: node_md_disks{state="failed"} > 0
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host RAID disk failure
        description: "At least one device in RAID array on {{ $labels.instance }} failed. Array {{ $labels.md_device }} needs attention and possibly a disk swap"

    - alert: HostKernelVersionDeviations
      expr: count(sum(label_replace(node_uname_info, "kernel", "$1", "release", "([0-9]+.[0-9]+.[0-9]+).*")) by (kernel)) > 1
      for: 6h
      labels:
        severity: warning
      annotations:
        summary: Host kernel version deviations
        description: "Different kernel versions are running"

    - alert: HostOomKillDetected
      expr: increase(node_vmstat_oom_kill[1m]) > 0
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Host OOM kill detected
        description: "OOM kill detected"

    - alert: HostEdacCorrectableErrorsDetected
      expr: increase(node_edac_correctable_errors_total[1m]) > 0
      for: 0m
      labels:
        severity: info
      annotations:
        summary: Host EDAC Correctable Errors detected
        description: "Host {{ $labels.instance }} has had {{ printf \"%.0f\" $value }} correctable memory errors reported by EDAC in the last minute."

    - alert: HostEdacUncorrectableErrorsDetected
      expr: node_edac_uncorrectable_errors_total > 0
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: Host EDAC Uncorrectable Errors detected
        description: "Host {{ $labels.instance }} has had {{ printf \"%.0f\" $value }} uncorrectable memory errors reported by EDAC in the last minute."

    - alert: HostNetworkReceiveErrors
      expr: rate(node_network_receive_errs_total[2m]) / rate(node_network_receive_packets_total[2m]) > 0.01
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host Network Receive Errors
        description: "Host {{ $labels.instance }} interface {{ $labels.device }} has encountered {{ printf \"%.0f\" $value }} receive errors in the last two minutes."

    - alert: HostNetworkTransmitErrors
      expr: rate(node_network_transmit_errs_total[2m]) / rate(node_network_transmit_packets_total[2m]) > 0.01
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host Network Transmit Errors
        description: "Host {{ $labels.instance }} interface {{ $labels.device }} has encountered {{ printf \"%.0f\" $value }} transmit errors in the last two minutes."

    - alert: HostNetworkInterfaceSaturated
      expr: (rate(node_network_receive_bytes_total[1m]) + rate(node_network_transmit_bytes_total[1m])) / node_network_speed_bytes > 0.8 < 10000
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: Host Network Interface Saturated
        description: "The network interface \"{{ $labels.device }}\" on \"{{ $labels.instance }}\" is getting overloaded."

    - alert: HostConntrackLimit
      expr: node_nf_conntrack_entries / node_nf_conntrack_entries_limit > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Host conntrack limit
        description: "The number of conntrack is approaching limit"

    - alert: HostClockSkew
      expr: (node_timex_offset_seconds > 0.05 and deriv(node_timex_offset_seconds[5m]) >= 0) or (node_timex_offset_seconds < -0.05 and deriv(node_timex_offset_seconds[5m]) <= 0)
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host clock skew
        description: "Clock skew detected. Clock is out of sync. Ensure NTP is configured correctly on this host."

    - alert: HostClockNotSynchronising
      expr: min_over_time(node_timex_sync_status[1m]) == 0 and node_timex_maxerror_seconds >= 16
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: Host clock not synchronising
        description: "Clock not synchronising. Ensure NTP is configured on this host."

    - alert: HostRequiresReboot
      expr: node_reboot_required > 0
      for: 4h
      labels:
        severity: info
      annotations:
        summary: Host requires reboot
        description: "{{ $labels.instance }} requires a reboot."
