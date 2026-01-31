# Maintenance Operations Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

This guide covers routine maintenance operations including Kubernetes upgrades, scaling, backup/disaster recovery, and state management.

---

## Kubernetes Version Upgrades

### Planning the Upgrade

**Check compatibility**:
```bash
# Current version
kubectl version --short

# Available versions
aws eks describe-addon-versions --kubernetes-version 1.31

# Check deprecations
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -A
```

### Upgrade Procedure

```bash
# 1. Update version in terraform.tfvars
vim providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfvars
# Change: cluster_version = "1.32"

# 2. Plan upgrade
cd providers/aws/regions/us-east-2/layers/02-platform/production
terraform plan

# 3. Apply (triggers rolling update)
terraform apply

# 4. Update kubeconfig
aws eks update-kubeconfig --name {cluster-name} --region us-east-2

# 5. Verify nodes
kubectl get nodes

# 6. Check for issues
kubectl get pods --all-namespaces | grep -v Running
```

**Upgrade Timeline**:
- Control plane: ~15 minutes
- Node group: ~30 minutes (rolling update)
- Total downtime: None (rolling update)

**Post-Upgrade**:
```bash
# Update cluster services (Layer 05)
cd providers/aws/regions/us-east-2/layers/05-cluster-services/production
terraform plan
terraform apply

# Restart workloads if needed
kubectl rollout restart deployment -n {namespace}
```

---

## Scaling Operations

### Scaling EKS Node Groups

**Horizontal Scaling** (add more nodes):

```bash
# Update clients.auto.tfvars
vim clients.auto.tfvars
# Change: 
#   desired_size = 5
#   max_size = 10

# Apply changes
cd providers/aws/regions/us-east-2/layers/02-platform/production
terraform plan
terraform apply

# Monitor scaling
kubectl get nodes --watch
```

**Vertical Scaling** (larger instance types):

```bash
# Update instance type
vim clients.auto.tfvars
# Change: instance_types = ["t3.large"]

# Apply (will recreate node group)
terraform plan
terraform apply

# Drain old nodes gradually
kubectl drain {old-node} --ignore-daemonsets --delete-emptydir-data
```

### Scaling Databases

**Increase storage**:
```bash
# Update EBS volume size
vim clients.auto.tfvars
# Change: data_volume_size = 200

cd providers/aws/regions/us-east-2/layers/03-database/production
terraform plan
terraform apply

# Extend filesystem (SSH to instance)
ssh admin@{db-ip}
sudo resize2fs /dev/nvme1n1
```

**Change instance type**:
```bash
# Stop application connections first
kubectl scale deployment {app} --replicas=0

# Update instance type
vim clients.auto.tfvars
# Change: instance_type = "r6i.xlarge"

terraform apply

# Restart application
kubectl scale deployment {app} --replicas=3
```

### Auto-Scaling Configuration

**Tune Cluster Autoscaler**:
```bash
# Update autoscaler settings
vim providers/aws/regions/us-east-2/layers/05-cluster-services/production/terraform.tfvars

# Adjust:
cluster_autoscaler_scale_down_enabled = true
cluster_autoscaler_scale_down_unneeded_time = "5m"
cluster_autoscaler_scale_down_delay_after_add = "10m"

terraform apply
```

---

## Backup and Disaster Recovery

### State File Backups

**Automatic Versioning** (already enabled):
```bash
# List versions
aws s3api list-object-versions \
  --bucket terraform-state-us-east-2-production \
  --prefix providers/aws/regions/us-east-2/layers/

# Download specific version
aws s3api get-object \
  --bucket terraform-state-us-east-2-production \
  --key us-east-2/02-platform/production/terraform.tfstate \
  --version-id {version-id} \
  terraform.tfstate.backup
```

**Manual Backup**:
```bash
# Backup all state files
aws s3 sync s3://terraform-state-us-east-2-production ./state-backup-$(date +%Y%m%d)

# Backup Layer 00 local state
cp providers/aws/regions/us-east-2/layers/00-bootstrap/production/terraform.tfstate \
   ./bootstrap-state-backup-$(date +%Y%m%d).tfstate
```

### Database Backups

**Automated EBS Snapshots** (configured):
```bash
# List snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:Client,Values={client-name}"

# Create manual snapshot
aws ec2 create-snapshot \
  --volume-id {volume-id} \
  --description "Manual backup for {client-name} - $(date +%Y-%m-%d)"
```

**PostgreSQL Logical Backup**:
```bash
# SSH to database instance
ssh admin@{db-ip}

# Full database dump
sudo -u postgres pg_dumpall > /backup/full-backup-$(date +%Y%m%d).sql

# Single database dump
sudo -u postgres pg_dump database_name > /backup/db-backup-$(date +%Y%m%d).sql

# Copy to S3
aws s3 cp /backup/*.sql s3://{client-name}-backups-us-east-2-production/postgres/
```

### Kubernetes Resource Backups

**Velero Setup** (recommended):
```bash
# Install Velero
velero install \
  --provider aws \
  --bucket {client-name}-velero-backups \
  --backup-location-config region=us-east-2 \
  --snapshot-location-config region=us-east-2

# Create backup schedule
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --ttl 720h0m0s

# Manual backup
velero backup create manual-backup-$(date +%Y%m%d)
```

**Manual Resource Export**:
```bash
# Backup all resources in namespace
kubectl get all -n {namespace} -o yaml > namespace-backup-$(date +%Y%m%d).yaml

# Backup ConfigMaps and Secrets
kubectl get configmap,secret -n {namespace} -o yaml > configs-backup-$(date +%Y%m%d).yaml
```

### Disaster Recovery Procedure

**Scenario: Complete Region Failure**

1. **Assess Impact**:
   ```bash
   # Check AWS service health
   aws health describe-events --region us-east-2
   
   # Test connectivity
   aws eks describe-cluster --name {cluster-name} --region us-east-2
   ```

2. **Activate DR Plan**:
   ```bash
   # Deploy to DR region (us-west-2)
   cd providers/aws/regions/us-west-2/layers/
   
   # Use same clients.auto.tfvars with different CIDR
   # Deploy all layers 00-06 in sequence
   ```

3. **Restore Data**:
   ```bash
   # Restore from S3 backups
   aws s3 sync s3://{client-name}-backups-us-east-2/ ./ --region us-west-2
   
   # Restore database
   ssh admin@{new-db-ip}
   sudo -u postgres psql < full-backup.sql
   ```

4. **Update DNS**:
   ```bash
   # Point Route53 to new region ALB
   aws route53 change-resource-record-sets \
     --hosted-zone-id {zone-id} \
     --change-batch file://dns-update.json
   ```

5. **Verify Services**:
   ```bash
   # Test application endpoints
   curl https://app.{client}.xyz.com/health
   
   # Verify monitoring
   kubectl port-forward -n observability svc/grafana 3000:80
   ```

---

## State Management

### State Locking

**Check Current Locks**:
```bash
# List all locks
aws dynamodb scan --table-name terraform-state-lock

# Check specific lock
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"terraform-state-us-east-2-production/us-east-2/02-platform/production/terraform.tfstate"}}'
```

**Force Unlock** (use with extreme caution):
```bash
# Get lock ID from error message
terraform force-unlock {lock-id}

# Or manually delete from DynamoDB
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"{lock-id}"}}'
```

### State Inspection

**View State**:
```bash
# Show all resources
terraform state list

# Show specific resource
terraform state show 'module.client_vpcs["acme-corp"].aws_vpc.this'

# Output state in JSON
terraform show -json > state.json
```

**Import Resources**:
```bash
# Import manually created resource
terraform import 'module.client_vpcs["client"].aws_vpc.this' vpc-12345678

# Verify import
terraform plan
```

### State Drift Resolution

**Detect Drift**:
```bash
# Refresh state from AWS
terraform refresh

# Check for drift
terraform plan -detailed-exitcode
```

**Fix Drift**:
```bash
# Option 1: Update Terraform to match AWS
terraform import ...

# Option 2: Update AWS to match Terraform
terraform apply

# Option 3: Update both to desired state
vim main.tf
terraform apply
```

---

## Certificate Management

### ACM Certificate Renewal

**Auto-renewal** (ACM handles automatically for DNS-validated certs):
```bash
# Check certificate status
aws acm list-certificates --region us-east-2

# Describe specific certificate
aws acm describe-certificate --certificate-arn {arn}
```

**Manual validation** (if needed):
```bash
# Get validation records
aws acm describe-certificate --certificate-arn {arn} \
  | jq '.Certificate.DomainValidationOptions'

# Add CNAME records to Route53
aws route53 change-resource-record-sets \
  --hosted-zone-id {zone-id} \
  --change-batch file://validation-record.json
```

---

## Log Rotation and Cleanup

### S3 Lifecycle Policies

**Already configured** in Layer 00:
- Logs: Archive to Glacier after 90 days, delete after 180 days
- Traces: Delete after 30 days
- Metrics: Delete after 14 days

**Manual Cleanup** (if needed):
```bash
# Delete old logs
aws s3 rm s3://{client}-logs-us-east-2-production/ \
  --recursive \
  --exclude "*" \
  --include "*2025*"

# Check bucket size
aws s3 ls s3://{client}-logs-us-east-2-production/ \
  --recursive \
  --human-readable \
  --summarize
```

### CloudWatch Log Groups

**Set retention**:
```bash
# Set retention period (days)
aws logs put-retention-policy \
  --log-group-name /aws/eks/{cluster-name}/cluster \
  --retention-in-days 30

# Delete old log groups
aws logs delete-log-group \
  --log-group-name /aws/vpc/flow-logs-old
```

---

## Monitoring Maintenance

### Prometheus Data Retention

**Adjust retention** (in Layer 06):
```bash
vim providers/aws/regions/us-east-2/layers/06-observability/production/terraform.tfvars
# Change: prometheus_retention_days = 15

terraform apply
```

**Manual Cleanup**:
```bash
# Access Prometheus pod
kubectl exec -n observability -it prometheus-0 -- sh

# Delete time series
curl -X POST \
  http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".+"}
```

### Grafana Dashboard Backups

**Export dashboards**:
```bash
# Port-forward Grafana
kubectl port-forward -n observability svc/grafana 3000:80

# Export via API
curl -H "Authorization: Bearer {api-key}" \
  http://localhost:3000/api/dashboards/uid/{dashboard-uid} \
  > dashboard-backup.json
```

---

## Routine Maintenance Checklist

### Daily
- [ ] Check cluster health: `kubectl get nodes`
- [ ] Review alerts in Grafana
- [ ] Monitor costs in AWS Cost Explorer

### Weekly
- [ ] Review pod resource usage: `kubectl top pods --all-namespaces`
- [ ] Check for pending OS updates
- [ ] Review CloudWatch logs for errors
- [ ] Verify backups are running

### Monthly
- [ ] Review and update security groups
- [ ] Audit IAM permissions
- [ ] Check for Terraform state drift
- [ ] Review S3 bucket sizes and lifecycle policies
- [ ] Test disaster recovery procedure
- [ ] Update documentation

### Quarterly
- [ ] Upgrade Kubernetes version
- [ ] Review and optimize costs
- [ ] Update Terraform modules
- [ ] Security audit
- [ ] Capacity planning review

---

## Emergency Procedures

### Complete Cluster Outage

```bash
# 1. Check AWS status
aws eks describe-cluster --name {cluster-name}

# 2. Check node status
kubectl get nodes

# 3. Force recreate node group
terraform taint 'module.eks_clusters["client"].aws_eks_node_group.this'
terraform apply

# 4. Notify team and stakeholders
```

### Database Corruption

```bash
# 1. Stop application
kubectl scale deployment {app} --replicas=0

# 2. Take snapshot
aws ec2 create-snapshot --volume-id {volume-id}

# 3. Restore from last good backup
# (See backup procedures above)

# 4. Verify data integrity
# 5. Restart application
```

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Initial deployment
- [Troubleshooting](TROUBLESHOOTING.md) - Problem solving
- [Security](SECURITY.md) - Security updates
- [Architecture](ARCHITECTURE.md) - System design

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
