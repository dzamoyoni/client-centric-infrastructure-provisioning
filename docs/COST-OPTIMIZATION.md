# Cost Optimization Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Cost Breakdown (3 Clients Example)

| Component | Monthly Cost | Per Client | Optimization |
|-----------|--------------|------------|--------------|
| Egress VPC NAT (2 AZs) | $65.70 | Shared | Use TGW routing |
| Transit Gateway | $146 | Shared | Cost-shared across clients |
| EKS clusters (3) | $219 | $73 | Control plane fixed cost |
| EKS nodes (t3.medium × 6) | ~$150 | $50 | Use Spot, autoscaler |
| Databases (PostgreSQL × 3) | ~$200 | $67 | Right-size instances |
| S3 + Observability | ~$50 | $17 | Lifecycle policies |
| **Total** | **~$830/month** | **~$277/client** | |

**NAT Gateway Savings**: $131/month (67% reduction vs per-client NAT)

---

## Resource Tagging Strategy

### Minimal Tags (6 base tags via provider default_tags)
```hcl
Environment  = "production"
CostCenter   = "CC-CLIENT-001"
Owner        = "Platform Engineering"
ManagedBy    = "Terraform"
Layer        = "foundation"
Project      = "client-centric-infra"
```

### Per-Client Tags (~14 additional tags)
```hcl
Client       = "acme-corp"
ClientCode   = "ACME"
Tier         = "standard"
Region       = "us-east-2"
# + resource-specific metadata
```

**Total**: ~20 tags per resource (well under 50-tag AWS limit)

---

## Per-Client Cost Tracking

```bash
# Generate cost report by client
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Client

# Cost by service per client
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter file://client-filter.json
```

---

## Optimization Strategies

### 1. Use Spot Instances (Non-Production)
```hcl
# In clients.auto.tfvars
eks = {
  capacity_type = "SPOT"  # 70% cheaper than ON_DEMAND
  instance_types = ["t3.medium", "t3a.medium"]  # Multiple for availability
}
```

### 2. Enable Cluster Autoscaler Scale-Down
```hcl
cluster_autoscaler_scale_down_enabled = true
cluster_autoscaler_scale_down_unneeded_time = "5m"
```

### 3. S3 Lifecycle Policies (Auto-configured)
- Logs → Glacier after 90 days, delete after 180 days
- Traces → Delete after 30 days
- Metrics → Delete after 14 days

### 4. Right-Size Instances
```bash
# Analyze usage
kubectl top nodes
kubectl top pods --all-namespaces

# Adjust in clients.auto.tfvars
instance_types = ["t3.small"]  # If under-utilized
```

### 5. Use EBS gp3 (Better Price/Performance)
Already configured - 20% cheaper than gp2 with same performance.

---

## Cost Monitoring

### Set Up Budgets
```bash
aws budgets create-budget \
  --account-id 123456789 \
  --budget file://budget-config.json \
  --notifications-with-subscribers file://notifications.json
```

### CloudWatch Cost Anomaly Detection
Enable in AWS Cost Explorer → Cost Anomaly Detection

---

## Related Documentation

- [Architecture](ARCHITECTURE.md) - Cost-optimized design
- [Getting Started](GETTING-STARTED.md) - Deployment
- [Maintenance](MAINTENANCE.md) - Routine operations

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
