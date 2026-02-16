# DNS Architecture - Layer Responsibilities

## Overview

This document clarifies the DNS management responsibilities split between **Layer 02 (Platform)** and **Layer 05 (Cluster Services)**.

## Architecture Diagram

```
Internet/VPN Client
        ↓
  DNS Resolution
        ↓
┌─────────────────────────────────────────────────┐
│  Route53 Hosted Zone: client-a.xyz             │
│  (Created by Layer 05)                          │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ Layer 02 Records (Terraform-Managed)   │    │
│  │ • app.client-a.xyz → ALB               │    │
│  │ • internal.client-a.xyz → Internal ALB │    │
│  │ • *.client-a.xyz → ALB (optional)      │    │
│  └────────────────────────────────────────┘    │
│                                                  │
│  ┌────────────────────────────────────────┐    │
│  │ Layer 05 Records (ExternalDNS-Managed) │    │
│  │ • api.client-a.xyz → Istio Gateway     │    │
│  │ • service1.client-a.xyz → K8s Service  │    │
│  │ • grafana.client-a.xyz → Monitoring    │    │
│  │ Dynamic based on K8s resources         │    │
│  └────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Layer 02 (Platform) - Terraform-Managed ALB DNS

**Purpose:** Static, infrastructure-level DNS for external load balancers

**What it manages:**
- ALB DNS records (internet-facing and internal)
- Entry point records for client domains
- Wildcard records (if enabled)

**Examples:**
```
app.client-a.xyz        → client-a-public-alb-123.us-east-2.elb.amazonaws.com
internal.client-a.xyz   → client-a-internal-alb-456.us-east-2.elb.amazonaws.com
*.client-a.xyz          → client-a-public-alb-123.us-east-2.elb.amazonaws.com (optional)
```

**Management:**
- Created by Terraform during Layer 02 deployment
- Static configuration in `/clients.auto.tfvars`
- Automatically discovers zones created by Layer 05
- Changes require `terraform apply`

**When to use:**
- External entry points to the client's infrastructure
- Load balancer endpoints
- Long-lived, stable DNS records

---

### Layer 05 (Cluster Services) - ExternalDNS-Managed Application DNS

**Purpose:** Dynamic, application-level DNS for Kubernetes services

**What it manages:**
- Kubernetes Service DNS records
- Istio Gateway/VirtualService DNS records
- Application-specific subdomains
- Dynamically created based on K8s annotations

**Examples:**
```
# Istio Gateway
api.client-a.xyz        → Istio IngressGateway (via annotation)

# Kubernetes Services
grafana.client-a.xyz    → Grafana Service LoadBalancer
prometheus.client-a.xyz → Prometheus Service
service1.client-a.xyz   → Application Service

# Application-specific
auth.client-a.xyz       → Auth Service
payments.client-a.xyz   → Payments Service
```

**Management:**
- Automatically created by ExternalDNS controller
- Watches Kubernetes resources (Services, Ingresses, Istio objects)
- Uses annotations on K8s resources:
  ```yaml
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.client-a.xyz
  ```
- No Terraform needed - fully automated

**When to use:**
- Kubernetes Service LoadBalancers
- Istio Gateways and VirtualServices
- Application microservices
- Dynamic services that change frequently

---

## Deployment Workflow

### Step 1: Deploy Layer 05 (Create Zones)
```bash
cd layers/05-cluster-services/production
terraform apply -var-file="../../../../../../clients.auto.tfvars"
```

**Creates:**
- Route53 hosted zones: `client-a.xyz`, `client-b.xyz`
- NS delegation records in parent zone
- ExternalDNS controller in each client's EKS cluster

**Output:**
```
client_zone_ids = {
  client-a = "Z1234567890ABCDEF"
  client-b = "Z9876543210FEDCBA"
}
```

### Step 2: Deploy Layer 02 (Create ALB DNS)
```bash
cd layers/02-platform/production
terraform apply -var-file="../../../../../../clients.auto.tfvars"
```

**Discovers:**
- Automatically finds zones by domain name (`client-a.xyz`)
- No zone IDs needed in configuration

**Creates:**
- ALB infrastructure
- DNS records pointing to ALBs

**Output:**
```
dns_zone_discovery_status = {
  client-a = {
    public_zone_found = true
    zone_id = "Z1234567890ABCDEF"
    status_message = "Zone discovered - DNS records created"
  }
}

client_endpoints = {
  client-a = {
    public_url = "https://app.client-a.xyz:30443"
    internal_url = "https://internal.client-a.xyz:30443"
    dns_status = "DNS records active"
  }
}
```

### Step 3: Deploy Kubernetes Applications (ExternalDNS Auto-Creates DNS)

When you deploy an Istio Gateway with annotation:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: api-gateway
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.client-a.xyz
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - api.client-a.xyz
```

**ExternalDNS automatically creates:**
```
api.client-a.xyz → a1b2c3d4-istio-ingressgateway-123.us-east-2.elb.amazonaws.com
```

---

## Do You Still Need ExternalDNS?

### ✅ **YES - Keep ExternalDNS** for:

1. **Dynamic Application DNS**
   - Kubernetes Services with LoadBalancer type
   - Istio Gateways and VirtualServices
   - Application microservices

2. **Developer Self-Service**
   - Developers can create DNS records by annotating K8s resources
   - No Terraform changes needed
   - No infrastructure team involvement

3. **Microservices Architecture**
   - Each service can have its own subdomain
   - Example: `auth.client-a.xyz`, `api.client-a.xyz`, `payments.client-a.xyz`

4. **Istio Service Mesh Integration**
   - Automatic DNS for VirtualServices
   - Multi-version routing with DNS (blue/green, canary)

### ❌ **Don't Use ExternalDNS** for:

1. **ALB Entry Points** (Use Layer 02 Terraform)
   - `app.client-a.xyz` → ALB
   - `internal.client-a.xyz` → Internal ALB

2. **Static Infrastructure** (Use Layer 02 Terraform)
   - Load balancer endpoints
   - VPN entry points
   - Long-lived infrastructure records

---

## Comparison Table

| Feature | Layer 02 (Terraform) | Layer 05 (ExternalDNS) |
|---------|---------------------|------------------------|
| **Purpose** | Infrastructure DNS | Application DNS |
| **Manages** | ALB records | K8s Service records |
| **Configuration** | `/clients.auto.tfvars` | K8s resource annotations |
| **Deployment** | `terraform apply` | Automatic (controller) |
| **Change Process** | Terraform workflow | Deploy K8s resource |
| **Use Case** | Entry points, LBs | Microservices, APIs |
| **Who Uses** | Infrastructure team | Developers + Infra |
| **Lifecycle** | Long-lived, stable | Dynamic, frequent changes |
| **Example** | `app.client-a.xyz` | `api.client-a.xyz` |

---

## Configuration Examples

### Layer 02 Configuration (`/clients.auto.tfvars`)

```hcl
clients = {
  client-a = {
    dns = {
      enabled                = true
      domain_name            = "client-a.xyz"      # Layer 05 creates this zone
      public_subdomain       = "app"               # → app.client-a.xyz
      internal_subdomain     = "internal"          # → internal.client-a.xyz
      create_route53_records = true
      create_wildcard_record = false
    }
  }
}
```

### Layer 05 ExternalDNS Configuration

**Istio Gateway Example:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: api-gateway
  namespace: istio-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.client-a.xyz
    external-dns.alpha.kubernetes.io/ttl: "300"
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - api.client-a.xyz
```

**Kubernetes Service Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    external-dns.alpha.kubernetes.io/hostname: grafana.client-a.xyz
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
  selector:
    app: grafana
```

---

## Traffic Flow Examples

### Example 1: Public Web Application
```
User Browser
    ↓ DNS: app.client-a.xyz
Layer 02 Terraform → ALB
    ↓ Port 30443 → 30080
EKS NodePort Service
    ↓ Port 80
Istio IngressGateway
    ↓ VirtualService routing
Application Pods
```

### Example 2: API Microservice
```
API Client
    ↓ DNS: api.client-a.xyz
Layer 05 ExternalDNS → Istio Gateway LoadBalancer
    ↓ Port 80
Istio IngressGateway
    ↓ VirtualService routing
API Service Pods
```

### Example 3: Monitoring Dashboard
```
Ops Team
    ↓ DNS: grafana.client-a.xyz
Layer 05 ExternalDNS → Grafana Service LoadBalancer
    ↓ Port 80
Grafana Pod
```

---

## Best Practices

### 1. Use Layer 02 (Terraform) for Infrastructure
- Main application entry points
- Load balancer endpoints
- Wildcard domains (if needed)
- Anything in `/clients.auto.tfvars`

### 2. Use Layer 05 (ExternalDNS) for Applications
- Microservice endpoints
- API gateways
- Developer-managed services
- Dynamic, frequently changing services

### 3. Naming Conventions
```
# Layer 02 (Infrastructure)
app.client-a.xyz          # Public web app entry
internal.client-a.xyz     # Internal VPN entry
*.client-a.xyz            # Wildcard (optional)

# Layer 05 (Applications)
api.client-a.xyz          # API gateway
auth.client-a.xyz         # Auth service
payments.client-a.xyz     # Payments service
grafana.client-a.xyz      # Monitoring
prometheus.client-a.xyz   # Metrics
```

### 4. Conflict Prevention
- Never create the same DNS record in both layers
- Use clear subdomain separation
- Document ownership in DNS records

---

## Troubleshooting

### Issue: DNS record not created by Layer 02

**Symptoms:**
```
dns_zone_discovery_status = {
  client-a = {
    public_zone_found = false
    status_message = "Zone not found - Deploy Layer 05 first"
  }
}
```

**Solution:**
1. Deploy Layer 05 first to create Route53 zones
2. Verify zone exists: `aws route53 list-hosted-zones`
3. Re-run Layer 02: `terraform apply`

### Issue: ExternalDNS not creating records

**Check:**
1. ExternalDNS pod running: `kubectl get pods -n kube-system -l app=external-dns`
2. View logs: `kubectl logs -n kube-system -l app=external-dns`
3. Verify annotation: `external-dns.alpha.kubernetes.io/hostname: api.client-a.xyz`
4. Check IAM permissions for ExternalDNS service account

### Issue: DNS record conflict

**Error:** Record already exists in Route53

**Solution:**
- Choose different subdomain
- Delete one of the conflicting records
- Document DNS record ownership

---

## Summary

| Layer | Purpose | Tool | Use Case |
|-------|---------|------|----------|
| **Layer 02** | Infrastructure DNS | Terraform | ALB entry points, static records |
| **Layer 05** | Application DNS | ExternalDNS | K8s services, Istio, microservices |

**Keep both!** They serve different purposes and complement each other perfectly.
