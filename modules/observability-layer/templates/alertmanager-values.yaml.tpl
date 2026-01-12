# AlertManager Helm Chart Values for Production Alerting
# Configured with Slack and email notifications

alertmanager:
  alertmanagerSpec:
    # Storage configuration
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${alertmanager_storage_class}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${storage_size}

    # Resource configuration
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi

    # Retention configuration
    retention: 120h # 5 days

    # Security context
    securityContext:
      runAsUser: 65534
      runAsGroup: 65534
      fsGroup: 65534

    # Configuration
    config:
      global:
        smtp_smarthost: 'localhost:587'
        smtp_from: 'alertmanager@${cluster_name}.local'
        smtp_auth_username: ''
        smtp_auth_password: ''
        slack_api_url: '${slack_webhook_url}'
        
      route:
        group_by: ['alertname', 'cluster', 'service', 'severity']
        group_wait: 10s
        group_interval: 10s
        repeat_interval: 1h
        receiver: 'default'
        routes:
        # Critical alerts go to email and Slack
        - match:
            severity: critical
          receiver: 'critical-alerts'
          group_wait: 0s
          repeat_interval: 5m
        # Warning alerts go to Slack
        - match:
            severity: warning
          receiver: 'slack-warnings'
        # Istio specific alerts
        - match:
            alertname: 'IstioServiceDown'
          receiver: 'istio-alerts'
        - match:
            alertname: 'IstioHighRequestLatency'
          receiver: 'istio-performance'

      receivers:
      - name: 'default'
        email_configs:
        - to: '${alert_email}'
          subject: '[ALERT] {{.GroupLabels.cluster}} - {{.GroupLabels.alertname}}'
          body: |
            Alert: {{.GroupLabels.alertname}}
            Cluster: {{.GroupLabels.cluster}}
            Severity: {{.GroupLabels.severity}}
            
            {{range .Alerts}}
            Instance: {{.Labels.instance}}
            Summary: {{.Annotations.summary}}
            Description: {{.Annotations.description}}
            {{end}}

      - name: 'critical-alerts'
        email_configs:
        - to: '${alert_email}'
          subject: '[CRITICAL] {{.GroupLabels.cluster}} - {{.GroupLabels.alertname}}'
          body: |
            🚨 CRITICAL ALERT 🚨
            
            Alert: {{.GroupLabels.alertname}}
            Cluster: {{.GroupLabels.cluster}}
            Severity: {{.GroupLabels.severity}}
            
            {{range .Alerts}}
            Instance: {{.Labels.instance}}
            Summary: {{.Annotations.summary}}
            Description: {{.Annotations.description}}
            {{end}}
        %{ if slack_webhook_url != "" }
        slack_configs:
        - channel: '#critical-alerts'
          username: 'AlertManager - CRITICAL'
          icon_emoji: ':rotating_light:'
          title: '🚨 CRITICAL ALERT - {{.GroupLabels.cluster}}'
          text: |
            *🚨 CRITICAL ALERT*
            *Alert:* {{.GroupLabels.alertname}}
            *Cluster:* {{.GroupLabels.cluster}}
            *Severity:* {{.GroupLabels.severity}}
            
            {{range .Alerts}}
            *Instance:* {{.Labels.instance}}
            *Summary:* {{.Annotations.summary}}
            *Description:* {{.Annotations.description}}
            {{end}}
        %{ endif }

      %{ if slack_webhook_url != "" }
      - name: 'slack-warnings'
        slack_configs:
        - channel: '#alerts-production'
          username: 'AlertManager'
          icon_emoji: ':warning:'
          title: 'Warning Alert - {{.GroupLabels.cluster}}'
          text: |
            *Alert:* {{.GroupLabels.alertname}}
            *Cluster:* {{.GroupLabels.cluster}}
            *Severity:* {{.GroupLabels.severity}}
            
            {{range .Alerts}}
            *Instance:* {{.Labels.instance}}
            *Summary:* {{.Annotations.summary}}
            *Description:* {{.Annotations.description}}
            {{end}}

      - name: 'istio-alerts'
        slack_configs:
        - channel: '#istio-alerts'
          username: 'Istio AlertManager'
          icon_emoji: ':triangular_flag_on_post:'
          title: 'Istio Service Mesh Alert - {{.GroupLabels.cluster}}'
          text: |
            *Service Mesh Alert*
            *Cluster:* {{.GroupLabels.cluster}}
            *Alert:* {{.GroupLabels.alertname}}
            
            {{range .Alerts}}
            *Service:* {{.Labels.destination_service_name}}
            *Namespace:* {{.Labels.destination_service_namespace}}
            *Summary:* {{.Annotations.summary}}
            {{end}}

      - name: 'istio-performance'
        slack_configs:
        - channel: '#performance-alerts'
          username: 'Istio Performance'
          icon_emoji: ':chart_with_downwards_trend:'
          title: 'Performance Issue - {{.GroupLabels.cluster}}'
          text: |
            *Performance Alert*
            *Cluster:* {{.GroupLabels.cluster}}
            *Alert:* {{.GroupLabels.alertname}}
            
            {{range .Alerts}}
            *Service:* {{.Labels.destination_service_name}}
            *Latency:* {{.Labels.response_time}}ms
            *Summary:* {{.Annotations.summary}}
            {{end}}
      %{ endif }

      inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'cluster', 'service']

# Service configuration
service:
  type: ClusterIP
  port: 9093

# Ingress configuration (disabled for security)
ingress:
  enabled: false

# Service monitor for Prometheus scraping
serviceMonitor:
  enabled: true
  interval: 30s

# Pod labels for identification
podLabels:
  app: alertmanager
  component: alerting
  layer: observability
  cluster: ${cluster_name}
  region: ${region}
