# Troubleshooting Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Common Issues

### 1. CIDR Conflicts

**Symptom**: Terraform fails with VPC peering or routing errors.

**Solution**:
```bash
# Run validation
./scripts/validate-cidr.sh

# Update conflicting client
vim providers/aws/regions/us-east-2/layers/01-foundation/production/clients.auto.tfvars

# Destroy and recreate (only if not in production!)
terraform destroy -target='module.client_vpcs["client-name"]'
terraform apply
```

**Prevention**:
- Always run `./scripts/validate-cidr.sh` before adding clients
- Keep `cidr-registry.yaml` up to date
- Use sequential CIDR allocation (10.100.0.0/16, 10.101.0.0/16, etc.)

---

### 2. EKS Cluster Unreachable

**Symptom**: `kubectl` commands timeout or connection refused.

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-2 \
  --name {cluster-name}

# Check security groups
aws eks describe-cluster --name {cluster-name} \
  | jq '.cluster.resourcesVpcConfig.clusterSecurityGroupId'

# Verify your IP is in management_cidr_blocks
vim providers/aws/regions/us-east-2/layers/02-platform/production/terraform.tfvars
```

**Common Causes**:
- IP not in `management_cidr_blocks`
- Security group misconfiguration
- VPN disconnected
- Cluster endpoint not public (if accessing from outside VPC)

---

### 3. State Lock Issues

**Symptom**: "Error acquiring the state lock"

**Solution**:
```bash
# Check lock in DynamoDB
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution!)
terraform force-unlock {lock-id}
```

**When to Force Unlock**:
- ✅ Previous terraform process crashed
- ✅ You're certain no one else is running terraform
- ❌ Another team member might be deploying
- ❌ CI/CD pipeline is running

**Prevention**:
- Coordinate deployments in team Slack channel
- Use CI/CD for production deployments
- Monitor for hung terraform processes

---

### 4. Node Group Not Scaling

**Symptom**: Pods stuck in Pending state, nodes not scaling up.

**Solution**:
```bash
# Check cluster autoscaler logs
kubectl --context {client} logs -n kube-system \
  -l app.kubernetes.io/name=cluster-autoscaler

# Verify IAM permissions
aws iam get-role-policy --role-name {autoscaler-role} \
  --policy-name {policy-name}

# Check node group limits
aws eks describe-nodegroup \
  --cluster-name {cluster-name} \
  --nodegroup-name {nodegroup-name}
```

**Common Causes**:
- Node group at max_size limit
- IAM permissions missing
- Insufficient EC2 capacity in region/AZ
- Autoscaler not installed (check Layer 05)

**Debug Commands**:
```bash
# Check pending pods
kubectl --context {client} get pods --all-namespaces | grep Pending

# Describe pending pod
kubectl --context {client} describe pod {pod-name} -n {namespace}

# Check autoscaler status
kubectl --context {client} get deployment -n kube-system cluster-autoscaler
```

---

### 5. DNS Not Resolving

**Symptom**: `nslookup app.client.xyz.com` fails or returns NXDOMAIN.

**Solution**:
```bash
# Check ExternalDNS logs
kubectl --context {client} logs -n kube-system \
  -l app.kubernetes.io/name=external-dns

# Verify Route53 zone
aws route53 list-resource-record-sets \
  --hosted-zone-id {zone-id}

# Check service annotation
kubectl --context {client} get svc {service-name} -o yaml \
  | grep external-dns
```

**Checklist**:
- [ ] ExternalDNS deployed (Layer 05)
- [ ] Route53 hosted zone exists
- [ ] Service/Ingress has correct annotation
- [ ] IAM role has Route53 permissions
- [ ] DNS propagation complete (wait 5-10 minutes)

**ExternalDNS Annotation**:
```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.client.xyz.com
```

---

### 6. Internet Connectivity Failures

**Symptom**: Pods cannot reach internet, timeouts connecting to external services.

**Solution**:
```bash
# Verify Transit Gateway attachment
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=vpc-id,Values={client-vpc-id}"

# Check client VPC route table
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values={client-vpc-id}"

# Verify NAT Gateway in Egress VPC
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values={egress-vpc-id}"

# Test from pod
kubectl --context {client} run test-pod --image=nicolaka/netshoot -it --rm -- bash
# Inside pod: curl -I https://www.google.com
```

**Common Causes**:
- Transit Gateway not attached
- Route table missing default route to TGW
- NAT Gateway not healthy
- Security groups blocking egress

---

### 7. Observability Stack Not Working

**Symptom**: Grafana unreachable, no metrics/logs appearing.

**Solution**:
```bash
# Check observability namespace
kubectl --context {client} get pods -n observability

# Check Prometheus targets
kubectl --context {client} port-forward -n observability svc/prometheus 9090:9090
# Open: http://localhost:9090/targets

# Check Loki logs
kubectl --context {client} logs -n observability -l app=loki

# Verify S3 buckets exist
aws s3 ls | grep {client}
```

**Service Health Check**:
```bash
# Prometheus
kubectl --context {client} get svc -n observability prometheus

# Grafana
kubectl --context {client} get svc -n observability grafana

# Loki
kubectl --context {client} get svc -n observability loki
```

---

### 8. Database Connection Failures

**Symptom**: Applications cannot connect to PostgreSQL.

**Solution**:
```bash
# Check database instance status
aws ec2 describe-instances \
  --filters "Name=tag:Client,Values={client}" "Name=tag:Role,Values=database"

# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids {db-security-group-id}

# Test connection from EKS
kubectl --context {client} run psql-test --image=postgres:15 -it --rm -- bash
# Inside pod: psql -h {db-ip} -U postgres -d postgres
```

**Security Group Requirements**:
- EKS security group must allow outbound to DB ports
- DB security group must allow inbound from EKS CIDR

---

### 9. Terraform State Drift

**Symptom**: Terraform shows unexpected changes on plan.

**Solution**:
```bash
# Refresh state from AWS
terraform refresh

# Check for manual changes
terraform plan -detailed-exitcode

# Import manually created resources
terraform import 'module.resource["name"].aws_resource.this' resource-id
```

**Prevention**:
- Avoid manual changes in AWS Console
- Use Terraform for all infrastructure changes
- Enable CloudTrail for audit logging

---

### 10. High Costs / Budget Exceeded

**Symptom**: AWS bill higher than expected.

**Investigation**:
```bash
# Per-client cost breakdown
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Client

# Check NAT Gateway data transfer
aws cloudwatch get-metric-statistics \
  --namespace AWS/NATGateway \
  --metric-name BytesOutToDestination \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-31T23:59:59Z \
  --period 86400 \
  --statistics Sum

# Check EKS node utilization
kubectl --context {client} top nodes
```

**Common Cost Culprits**:
- Oversized EKS nodes (use t3.medium for dev)
- NAT Gateway data transfer (optimize egress)
- Unused EBS volumes
- Non-optimized S3 storage (enable lifecycle policies)

📘 **More**: [Cost Optimization Guide](COST-OPTIMIZATION.md)

---

## Debugging Commands

### Kubernetes Debugging

```bash
# Get all resources in namespace
kubectl --context {client} get all -n {namespace}

# Describe failing pod
kubectl --context {client} describe pod {pod-name} -n {namespace}

# View pod logs
kubectl --context {client} logs {pod-name} -n {namespace}

# Get events (sorted by time)
kubectl --context {client} get events --sort-by='.lastTimestamp'

# Check node resources
kubectl --context {client} describe node {node-name}
```

### AWS Resource Debugging

```bash
# List all VPCs
aws ec2 describe-vpcs --output table

# List all EKS clusters
aws eks list-clusters --region us-east-2

# Check Transit Gateway status
aws ec2 describe-transit-gateways

# View CloudWatch logs
aws logs tail /aws/eks/{cluster-name}/cluster --follow
```

### Terraform Debugging

```bash
# Enable detailed logging
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform-debug.log

# Show state
terraform show

# List resources in state
terraform state list

# Show specific resource
terraform state show 'module.resource["name"].aws_resource.this'
```

---

## Emergency Procedures

### Cluster Completely Unreachable

```bash
# 1. Check AWS Console - is cluster running?
# 2. Verify AWS credentials
aws sts get-caller-identity

# 3. Update kubeconfig
aws eks update-kubeconfig --region us-east-2 --name {cluster}

# 4. Check security groups in AWS Console
# 5. Verify Transit Gateway routes
# 6. Contact platform team if still failing
```

### Mass Pod Failures

```bash
# 1. Check node status
kubectl --context {client} get nodes

# 2. Check for resource exhaustion
kubectl --context {client} top nodes
kubectl --context {client} describe nodes

# 3. Scale down non-critical workloads
kubectl --context {client} scale deployment {deployment} --replicas=0

# 4. Check for failed deployments
kubectl --context {client} get deployments --all-namespaces
```

### Database Down

```bash
# 1. Check instance status in AWS Console
# 2. Review CloudWatch logs
# 3. Attempt restart (only if safe)
aws ec2 reboot-instances --instance-ids {db-instance-id}

# 4. Check EBS volume status
aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values={instance-id}"
```

---

## Getting Help

When asking for help, include:

1. **Exact error message** (full output)
2. **Layer being deployed** (e.g., Layer 02 - Platform)
3. **Client name** (if applicable)
4. **What you've tried** (troubleshooting steps)
5. **Recent changes** (last 24 hours)

**Channels**:
- **Slack**: #platform-engineering
- **Email**: platform-team@company.com
- **Urgent**: PagerDuty on-call

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Initial deployment
- [Architecture](ARCHITECTURE.md) - How things work
- [Maintenance](MAINTENANCE.md) - Routine operations
- [Security](SECURITY.md) - Security issues

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
