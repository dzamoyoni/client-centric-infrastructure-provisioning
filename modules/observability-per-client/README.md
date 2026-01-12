# Observability Per-Client Module

Complete observability stack for per-client isolated EKS clusters with metrics, logs, traces, and alerting.

## Features

- **Complete Isolation**: Each client gets dedicated observability stack in their own namespace
- **Metrics**: Prometheus with configurable retention and HA support
- **Visualization**: Grafana with pre-configured dashboards and auto-configured datasources
- **Alerting**: AlertManager with per-client email/Slack routing
- **Logs**: Loki distributed with S3 backend storage
- **Traces**: Tempo with multi-protocol support (OTLP, Jaeger, Zipkin)
- **Log Collection**: Fluent Bit DaemonSet on all nodes
- **S3 Storage**: Client-specific prefixes for cost-efficient data isolation
- **IRSA**: Secure IAM roles for S3 access
- **Tier-Based**: Premium and standard configurations

## Architecture

```
Client Namespace: {client-name}-monitoring
├── Prometheus (2 replicas for premium, 1 for standard)
├── Grafana (with auto-configured datasources)
├── AlertManager (client-specific routing)
├── Loki Distributed
│   ├── Ingester
│   ├── Querier
│   ├── Query Frontend
│   ├── Compactor
│   ├── Gateway
│   └── Memcached
├── Tempo (multi-protocol tracing)
├── Fluent Bit (DaemonSet on all nodes)
└── Node Exporter (DaemonSet)

S3 Storage:
├── shared-logs-bucket/clients/{client-name}/logs/
├── shared-traces-bucket/clients/{client-name}/traces/
└── shared-metrics-bucket/clients/{client-name}/metrics/
```

## Usage

```hcl
module "client_observability" {
  source = "./modules/observability-per-client"
  
  # Client identification
  client_name     = "est-test-a"
  client_tier     = "premium"  # or "standard"
  client_code     = "ETA"
  cost_center     = "IT-Infrastructure"
  business_unit   = "Platform-Engineering"
  
  # Cluster configuration
  cluster_name            = "ezra-terraform-est-test-a-us-east-2"
  cluster_endpoint        = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate  = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  oidc_provider_arn       = "arn:aws:iam::123456789:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/XXXXX"
  oidc_provider_url       = "oidc.eks.us-east-2.amazonaws.com/id/XXXXX"
  
  vpc_id      = "vpc-xxxxx"
  region      = "us-east-2"
  project_name = "ezra-terraform"
  environment  = "production"
  
  # S3 buckets (shared with client prefixes)
  shared_logs_bucket        = "ezra-terraform-us-east-2-logs-production"
  shared_logs_bucket_arn    = "arn:aws:s3:::ezra-terraform-us-east-2-logs-production"
  shared_traces_bucket      = "ezra-terraform-us-east-2-traces-production"
  shared_traces_bucket_arn  = "arn:aws:s3:::ezra-terraform-us-east-2-traces-production"
  shared_metrics_bucket     = "ezra-terraform-us-east-2-metrics-production"
  shared_metrics_bucket_arn = "arn:aws:s3:::ezra-terraform-us-east-2-metrics-production"
  
  # Observability configuration
  prometheus_retention      = "15d"
  prometheus_retention_size = "40GB"
  prometheus_storage        = "50Gi"  # or "100Gi" for premium
  prometheus_replicas       = 2       # or 1 for standard
  
  loki_retention_days   = 7  # or 30 for premium
  tempo_retention_hours = 168  # 7 days
  
  grafana_admin_password = var.grafana_admin_password
  grafana_storage        = "20Gi"  # or "50Gi" for premium
  
  # Alerting (optional)
  alert_email       = "alerts@example.com"
  slack_webhook_url = var.slack_webhook_url
  
  # Feature flags
  enable_fluent_bit    = true
  enable_loki          = true
  enable_tempo         = true
  enable_node_exporter = true
  
  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Outputs

- `namespace`: Monitoring namespace name
- `prometheus_url`: Prometheus service URL (cluster-internal)
- `grafana_url`: Grafana service URL (cluster-internal)
- `alertmanager_url`: AlertManager service URL (cluster-internal)
- `loki_url`: Loki gateway URL (cluster-internal)
- `tempo_url`: Tempo service URL (cluster-internal)
- `grafana_port_forward`: kubectl port-forward command for Grafana
- `prometheus_port_forward`: kubectl port-forward command for Prometheus
- `components_deployed`: Status of all components
- `configuration`: Configuration summary

## Accessing Grafana

```bash
# Port forward to Grafana
kubectl port-forward -n est-test-a-monitoring svc/est-test-a-grafana 3000:80

# Open browser
open http://localhost:3000

# Login
# Username: admin
# Password: <grafana_admin_password>
```

## Cost Estimate

### Standard Tier (~$19-24/month)
- Prometheus Storage (50Gi): $5/month
- Grafana Storage (20Gi): $2/month
- Loki/Tempo Local Storage: $2/month
- S3 Storage (logs/traces): $10-15/month
- Compute: Included in node costs

### Premium Tier (~$40-50/month)
- Prometheus Storage (100Gi): $10/month
- Grafana Storage (50Gi): $5/month
- Loki/Tempo Local Storage: $5/month
- S3 Storage (logs/traces): $20-30/month
- HA with 2 Prometheus replicas
- Longer retention (30 days)

## Tier Differences

| Feature | Standard | Premium |
|---------|----------|---------|
| Prometheus Replicas | 1 | 2 (HA) |
| Prometheus Storage | 50Gi | 100Gi |
| Prometheus Retention | 15 days | 30 days |
| Grafana Storage | 20Gi | 50Gi |
| Loki Retention | 7 days | 30 days |
| Tempo Retention | 7 days | 14 days |
| AlertManager Replicas | 1 | 2 (HA) |

## Components

### Prometheus Stack
- **Prometheus**: Time-series metrics database
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Node Exporter**: Node-level metrics (DaemonSet)
- **Kube State Metrics**: Kubernetes object metrics

### Loki Distributed
- **Ingester**: Receives and writes logs to S3
- **Querier**: Queries logs from S3
- **Query Frontend**: Load balancing for queries
- **Compactor**: Compacts data and manages retention
- **Gateway**: Unified access point
- **Memcached**: Query result caching

### Tempo
- **OTLP**: gRPC (4317) and HTTP (4318)
- **Jaeger**: gRPC (14250), HTTP (14268), Compact (6831), Binary (6832)
- **Zipkin**: HTTP (9411)
- S3 backend for trace storage

### Fluent Bit
- DaemonSet on ALL nodes
- Collects logs from all pods
- Outputs to Loki (real-time) and S3 (long-term)
- Client-specific labels automatically added

## Pre-Configured Dashboards

Grafana includes:
- Kubernetes Cluster Monitoring (GrafanaNet 7249)
- Kubernetes Pod Monitoring (GrafanaNet 6336)
- Node Exporter Full
- Prometheus Stats

## Data Flow

### Metrics
```
Pod → Prometheus → PV (15-30 days) → Grafana
```

### Logs
```
Pod → Fluent Bit → Loki → S3 (client prefix) → Grafana
                  ↓
                  S3 (long-term storage)
```

### Traces
```
Application → Tempo → S3 (client prefix) → Grafana
```

## Requirements

- Kubernetes 1.27+
- EKS cluster with OIDC provider
- S3 buckets for logs, traces, metrics
- Storage class: gp2-csi
- Helm 3.x

## Module Files

- `versions.tf`: Provider requirements
- `variables.tf`: All configurable variables (248 lines)
- `main.tf`: Provider config and locals
- `namespace.tf`: Per-client monitoring namespace
- `storage-class.tf`: GP2-CSI storage class
- `iam.tf`: IAM roles for IRSA (213 lines)
- `prometheus.tf`: Prometheus stack (340 lines)
- `loki.tf`: Loki distributed (239 lines)
- `tempo.tf`: Tempo tracing (216 lines)
- `fluent-bit.tf`: Fluent Bit DaemonSet (197 lines)
- `outputs.tf`: Module outputs (134 lines)

**Total**: ~1,800 lines of production-grade observability configuration

## Security

- **IRSA**: All S3 access via IAM roles, no static credentials
- **Client Prefixes**: S3 data isolated via prefixes
- **RBAC**: Kubernetes RBAC via namespace isolation
- **Network**: ClusterIP services, no external exposure
- **Encryption**: All S3 data encrypted at rest

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n est-test-a-monitoring
```

### View Logs
```bash
# Prometheus
kubectl logs -n est-test-a-monitoring est-test-a-prometheus-0

# Grafana
kubectl logs -n est-test-a-monitoring -l app.kubernetes.io/name=grafana

# Loki Ingester
kubectl logs -n est-test-a-monitoring -l app=loki,component=ingester
```

### Verify S3 Access
```bash
# Check Fluent Bit S3 writes
aws s3 ls s3://bucket-name/clients/est-test-a/logs/ --recursive

# Check Tempo S3 writes
aws s3 ls s3://bucket-name/clients/est-test-a/traces/ --recursive
```

## Support

For issues or questions, refer to:
- `/home/dennis.juma/ezra-terraform/LAYER_06_OBSERVABILITY_REFACTOR_PLAN.md`
- `/home/dennis.juma/ezra-terraform/OBSERVABILITY_MODULE_STATUS.md`
