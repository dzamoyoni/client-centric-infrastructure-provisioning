# Security Best Practices

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

This guide covers security best practices for the client-centric infrastructure, including secrets management, access control, encryption, and compliance.

---

## Secrets Management

### 1. Never Commit Secrets to Git

**Critical**: Secrets must NEVER be committed to version control.

```bash
# Add to .gitignore (if not already present)
echo "*secrets*.tfvars" >> .gitignore
echo "*.pem" >> .gitignore
echo "*.key" >> .gitignore
echo ".env" >> .gitignore
```

**Verify no secrets in history**:
```bash
# Scan repository for potential secrets
git log --all --full-history --source -- '*secret*' '*password*' '*.pem'
```

---

### 2. Use AWS Secrets Manager

Store sensitive data in AWS Secrets Manager, not in terraform files.

**Create secret**:
```bash
aws secretsmanager create-secret \
  --name /terraform/client-name/db-password \
  --secret-string '{"password":"SecurePass123!"}'
```

**Retrieve in Terraform**:
```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "/terraform/${var.client_name}/db-password"
}

locals {
  db_password = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]
}
```

**Rotate secrets regularly**:
```bash
# Update secret
aws secretsmanager update-secret \
  --secret-id /terraform/client-name/db-password \
  --secret-string '{"password":"NewSecurePass456!"}'
```

---

### 3. Database Secrets Handling

For Layer 03 (Database), create a local secrets file:

```bash
cat > database-secrets.tfvars << 'EOF'
database_passwords = {
  "client-name" = "SecurePassword123!"
}

replication_passwords = {
  "client-name" = "ReplicaPassword456!"
}
EOF

# Set restrictive permissions
chmod 600 database-secrets.tfvars
```

**Never commit this file**. Share via secure channels (1Password, Vault, etc.).

---

## Access Control

### 1. Enable MFA for Terraform Operations

All AWS users running Terraform should use MFA.

```bash
# Get MFA session token
aws sts get-session-token \
  --serial-number arn:aws:iam::123456789:mfa/username \
  --token-code 123456

# Export credentials (from output)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

**Terraform backend with MFA**:
```hcl
terraform {
  backend "s3" {
    bucket  = "terraform-state-us-east-2-production"
    key     = "us-east-2/layer/terraform.tfstate"
    region  = "us-east-2"
    encrypt = true
    
    # MFA enforced via bucket policy
    kms_key_id     = "alias/terraform-state-production"
    dynamodb_table = "terraform-state-lock"
  }
}
```

---

### 2. Restrict State Bucket Access

**S3 Bucket Policy** (enforce MFA and specific IAM roles):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789:role/TerraformRole"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::terraform-state-us-east-2-production/providers/aws/*"
    },
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::terraform-state-us-east-2-production/*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Apply policy**:
```bash
aws s3api put-bucket-policy \
  --bucket terraform-state-us-east-2-production \
  --policy file://bucket-policy.json
```

---

### 3. Tag-Based Access Control (TBAC)

Restrict access to resources based on tags.

**IAM Policy Example** (limit to specific client):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Client": "acme-corp"
        }
      }
    }
  ]
}
```

---

## Encryption

### 1. Encryption at Rest

All data stores must use encryption at rest.

**S3 Buckets** (already configured in Layer 00):
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}
```

**EBS Volumes** (EKS nodes):
```hcl
eks = {
  disk_size    = 50
  encrypted    = true  # Always enable
  kms_key_arn  = aws_kms_key.ebs.arn
}
```

**Database Volumes**:
All EBS volumes for PostgreSQL are encrypted with KMS.

---

### 2. Encryption in Transit

**Enforce TLS everywhere**:

```yaml
# Kubernetes Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
  - host: myapp.client.xyz.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

**Database connections**: Always use SSL/TLS.

```bash
# PostgreSQL with SSL
psql "postgresql://user@host:5432/db?sslmode=require"
```

---

### 3. KMS Key Management

**Key rotation**: Enabled automatically for all KMS keys.

```hcl
resource "aws_kms_key" "terraform_state" {
  description             = "Terraform state encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true  # Automatic annual rotation
  
  tags = merge(
    local.common_tags,
    {
      Name = "terraform-state-${var.environment}"
    }
  )
}
```

**Verify rotation**:
```bash
aws kms get-key-rotation-status --key-id alias/terraform-state-production
```

---

## Network Security

### 1. Security Groups (Least Privilege)

**EKS Nodes**:
- Inbound: Only from ALB security group
- Outbound: To internet via Transit Gateway

**Database**:
- Inbound: Only from EKS security group on port 5432
- Outbound: None required

**NAT Gateway** (Egress VPC):
- Managed by AWS, no SG required

---

### 2. VPC Flow Logs

Enable for all VPCs (already configured):

```hcl
resource "aws_flow_log" "client_vpc" {
  vpc_id          = aws_vpc.client.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
}
```

**Query flow logs**:
```bash
# CloudWatch Insights query
aws logs start-query \
  --log-group-name "/aws/vpc/flow-logs" \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, srcAddr, dstAddr, action | filter action = "REJECT"'
```

---

### 3. Network Isolation

**Client VPCs are isolated by default**:
- No cross-client communication
- Transit Gateway doesn't route between client VPCs
- Egress-only routing

**To enable cross-client communication** (rare):
```hcl
# Add route in Transit Gateway route table
resource "aws_ec2_transit_gateway_route" "client_to_client" {
  destination_cidr_block         = "10.101.0.0/16"  # Client B
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.client_a.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}
```

---

## Compliance & Auditing

### 1. CloudTrail

Enable CloudTrail for all API activity:

```bash
# Check if enabled
aws cloudtrail describe-trails

# View recent events
aws cloudtrail lookup-events \
  --max-items 50 \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::EC2::Instance
```

---

### 2. AWS Config

Monitor configuration compliance:

```bash
# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::EC2::Instance

# Get non-compliant resources
aws configservice describe-compliance-by-config-rule \
  --config-rule-names required-tags
```

---

### 3. Regular Security Audits

**Monthly checklist**:

```bash
# 1. Check for open security groups
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[?IpPermissions[?ToPort==`22` || ToPort==`3389`]]'

# 2. Review IAM policies
aws iam get-account-authorization-details > iam-audit.json

# 3. Check S3 bucket security
./scripts/verify-s3-security.sh

# 4. Review unused resources
aws ec2 describe-volumes --filters "Name=status,Values=available"
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null]'

# 5. Check encryption status
aws rds describe-db-instances --query 'DBInstances[?!StorageEncrypted]'
```

---

## Kubernetes Security

### 1. RBAC (Role-Based Access Control)

**Create limited-access role**:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind:Role
metadata:
  name: developer
  namespace: default
rules:
- apiGroups: ["", "apps"]
  resources: ["pods", "deployments", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: default
subjects:
- kind: User
  name: developer@company.com
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

---

### 2. Pod Security Standards

**Enforce restricted pod security**:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

### 3. Network Policies

**Restrict pod-to-pod communication**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

## Incident Response

### Security Breach Procedure

1. **Immediate Actions**:
   ```bash
   # Revoke compromised credentials
   aws iam delete-access-key --access-key-id AKIA...
   
   # Rotate secrets
   aws secretsmanager rotate-secret --secret-id /terraform/...
   
   # Review CloudTrail for unauthorized activity
   aws cloudtrail lookup-events --max-items 1000
   ```

2. **Containment**:
   - Isolate affected resources
   - Block suspicious IPs in security groups
   - Disable compromised IAM users/roles

3. **Investigation**:
   - Review VPC Flow Logs
   - Check CloudWatch Logs
   - Analyze CloudTrail events

4. **Recovery**:
   - Restore from known-good state
   - Apply security patches
   - Update access controls

5. **Post-Incident**:
   - Document lessons learned
   - Update security policies
   - Conduct team review

---

## Security Checklist

**Before Production Deployment**:

- [ ] All secrets in AWS Secrets Manager (not in code)
- [ ] MFA enabled for all human users
- [ ] State bucket access restricted to specific IAM roles
- [ ] KMS encryption enabled for all data stores
- [ ] VPC Flow Logs enabled
- [ ] CloudTrail enabled and logging to S3
- [ ] Security groups follow least-privilege
- [ ] No SSH keys in Terraform code
- [ ] database-secrets.tfvars in .gitignore
- [ ] Regular backup schedule configured
- [ ] Monitoring and alerting configured
- [ ] Incident response plan documented

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Initial setup
- [Architecture](ARCHITECTURE.md) - Security architecture
- [Troubleshooting](TROUBLESHOOTING.md) - Security issues
- [Maintenance](MAINTENANCE.md) - Security updates

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
