# Architecture Deep Dive

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Hub-and-Spoke Network Model](#hub-and-spoke-network-model)
3. [CIDR Allocation Strategy](#cidr-allocation-strategy)
4. [Traffic Flow Patterns](#traffic-flow-patterns)
5. [VPN Integration](#vpn-integration)
6. [Cost Optimization Rationale](#cost-optimization-rationale)

---

## Design Philosophy

This infrastructure implements **true client-centric architecture** where:

### Core Principles

1. **Hard Isolation**: Each client gets dedicated infrastructure
   - Separate VPC with unique CIDR
   - Isolated EKS cluster
   - Dedicated databases and compute
   - Per-client observability stack

2. **Centralized Egress**: Single shared path to internet
   - One Egress VPC with NAT Gateways
   - Cost-shared across all clients
   - Centralized security controls
   - Simplified network management

3. **Scalability**: Add clients without infrastructure duplication
   - No per-client NAT Gateways
   - Shared Transit Gateway
   - Automated CIDR allocation
   - 254 possible clients (10.0.0.0/8 - 10.254.0.0/8)

4. **Security by Default**:
   - Network isolation at VPC level
   - Security groups per workload type
   - VPC Flow Logs enabled
   - KMS encryption for state and data

---

## Hub-and-Spoke Network Model

### Architecture Overview

```
                          Internet
                             │
                    Internet Gateway
                             │
                    ┌────────┴────────┐
                    │   Egress VPC    │
                    │  10.255.0.0/16  │
                    │  (NAT Gateways) │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │ Transit Gateway │  ← Hub
                    │  (Routing Hub)  │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────┴─────┐    ┌────┴────┐    ┌─────┴─────┐
      │ Client A  │    │Client B │    │ Client C  │  ← Spokes
      │10.100.0/16│    │10.101../16│    │10.102../16│
      │(NAT-less) │    │(NAT-less)│    │(NAT-less) │
      └───────────┘    └─────────┘    └───────────┘
```

### Components

#### Egress VPC (Hub)
- **CIDR**: 10.255.0.0/16 (reserved)
- **Purpose**: Centralized internet egress
- **Resources**:
  - 2 Public subnets (AZ a, b) with Internet Gateway
  - 2 NAT Gateways (high availability)
  - Transit Gateway attachment
  - VPC Flow Logs

#### Client VPCs (Spokes)
- **CIDR**: 10.X.0.0/16 (X = 0-254, excluding 255)
- **Purpose**: Isolated client workloads
- **Resources**:
  - Public subnets (for load balancers)
  - Private subnets (for general workloads)
  - EKS subnets (/20 for large pod IP space)
  - Database subnets
  - Compute subnets
  - **NO NAT Gateways** (cost optimization)

#### Transit Gateway (Hub)
- **Purpose**: Central routing between all VPCs
- **Features**:
  - Auto-accept attachments
  - Dynamic route propagation
  - Flow logs enabled
  - ASN: 64512 (default)

---

## CIDR Allocation Strategy

### Overall Scheme

| Range | Purpose | Count |
|-------|---------|-------|
| 10.0.0.0/16 - 10.254.0.0/16 | Client VPCs | 255 |
| 10.255.0.0/16 | Egress VPC (reserved) | 1 |

### Per-Client VPC Subnets

For a client VPC with CIDR `10.X.0.0/16`:

```
Subnet Type    | CIDR Blocks             | Size    | Purpose
---------------|-------------------------|---------|------------------
Public         | 10.X.0.0/24             | 256 IPs | Load balancers
               | 10.X.1.0/24             | 256 IPs | (AZ b)
---------------|-------------------------|---------|------------------
Private        | 10.X.2.0/24             | 256 IPs | General workloads
               | 10.X.3.0/24             | 256 IPs | (AZ b)
---------------|-------------------------|---------|------------------
EKS            | 10.X.16.0/20            | 4096 IPs| Kubernetes pods
               | 10.X.32.0/20            | 4096 IPs| (AZ b)
---------------|-------------------------|---------|------------------
Database       | 10.X.48.0/24            | 256 IPs | PostgreSQL
               | 10.X.49.0/24            | 256 IPs | (AZ b)
---------------|-------------------------|---------|------------------
Compute        | 10.X.64.0/24            | 256 IPs | Analytics/batch
               | 10.X.65.0/24            | 256 IPs | (AZ b)
```

### CIDR Registry

Centralized tracking in `cidr-registry.yaml`:

```yaml
clients:
  client-a:
    vpc_cidr: "10.100.0.0/16"
    region: "us-east-2"
    environment: "production"
    allocated_date: "2026-01-15"
    
  client-b:
    vpc_cidr: "10.101.0.0/16"
    region: "us-east-2"
    environment: "production"
    allocated_date: "2026-01-20"
```

**Validation**: Run `./scripts/validate-cidr.sh` before adding new clients.

---

## Traffic Flow Patterns

### 1. Internet-Bound Traffic (Client → Internet)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
│   EKS Pod   │────▶│Private Route│────▶│   Transit   │────▶│  Egress  │
│ 10.100.20.5 │     │    Table    │     │   Gateway   │     │    VPC   │
└─────────────┘     │  0.0.0.0/0  │     │             │     │          │
                    │  via TGW    │     │             │     │          │
                    └─────────────┘     └─────────────┘     └─────┬────┘
                                                                    │
                    ┌───────────────────────────────────────────────┘
                    │
                    ▼
            ┌───────────────┐     ┌──────────────┐
            │  NAT Gateway  │────▶│   Internet   │
            │ (Egress VPC)  │     │   Gateway    │
            └───────────────┘     └──────────────┘
```

**Flow Details**:
1. Pod in Client VPC sends packet to internet
2. Private subnet route table directs to Transit Gateway
3. Transit Gateway routes to Egress VPC
4. Egress VPC NAT Gateway translates source IP
5. Internet Gateway sends to internet

### 2. Cross-Client Traffic (Optional)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Client A   │────▶│   Transit   │────▶│  Client B   │
│    Pod      │     │   Gateway   │     │   Service   │
└─────────────┘     └─────────────┘     └─────────────┘
```

**Note**: By default, client VPCs cannot communicate. Enable by adding routes in Transit Gateway route tables.

### 3. VPN-Enabled Client Traffic

```
On-Premises Network                    AWS Cloud
┌────────────────┐                    ┌─────────────┐
│Customer Gateway│◄──────IPSec────────┤VPN Gateway  │
│  192.168.0.1   │      Tunnel        │(Client VPC) │
└────────────────┘                    └──────┬──────┘
                                             │
                                             │ Longest-prefix match
                                             │ 192.168.0.0/24 → VPN
                                             │ 0.0.0.0/0 → TGW
                                             │
                                        ┌────┴────┐
                                        │Client VPC│
                                        │Route Tbl │
                                        └──────────┘
```

**Key Point**: VPN routes (specific) take precedence over default route (TGW).

---

## VPN Integration

### Design

VPN-enabled clients get:
1. **VPN Gateway** attached to their VPC
2. **Customer Gateway** representing on-premises device
3. **Site-to-Site VPN** with two tunnels (HA)
4. **Route Propagation** for on-premises CIDRs

### Routing Behavior

**VPN Gateway** (attached to VPC) vs **Transit Gateway** (hub):
- VPN Gateway handles on-premises traffic (e.g., 192.168.0.0/24)
- Transit Gateway handles internet traffic (0.0.0.0/0)
- **Longest-prefix match** ensures correct routing

Example route table:
```
Destination         Target              Priority
192.168.0.0/24  →  VPN Gateway (vgw-*)  Specific (wins)
0.0.0.0/0       →  Transit Gateway      Default (fallback)
```

### Configuration

In `clients.auto.tfvars`:

```hcl
vpn = {
  enabled              = true
  customer_gateway_ip  = "203.0.113.10"
  bgp_asn             = 65001
  amazon_side_asn     = 64512
  static_routes_only  = true
  local_network_cidr  = "192.168.0.0/24"
  tunnel1_inside_cidr = "169.254.10.0/30"
  tunnel2_inside_cidr = "169.254.11.0/30"
}
```

📘 **More Details**: [Networking Guide](NETWORKING.md#vpn-integration)

---

## Cost Optimization Rationale

### NAT Gateway Savings

**Traditional Approach** (per-client NAT):
```
3 clients × 2 NAT Gateways × $32.85/month = $197.10/month
```

**Our Approach** (shared NAT):
```
1 Egress VPC × 2 NAT Gateways × $32.85/month = $65.70/month
Savings: $131.40/month (67% reduction)
```

**With 10 clients**:
```
Traditional: $657/month
Our approach: $65.70/month
Savings: $591.30/month (90% reduction)
```

### Transit Gateway Costs

- **Attachment**: $36.50/month per VPC
- **Data Transfer**: $0.02/GB

**Cost Model** (3 clients):
```
Attachments: 4 VPCs × $36.50 = $146/month
Data transfer: ~100GB/client × 3 × $0.02 = $6/month
Total: ~$152/month

Compare to NAT savings: $131.40/month
Net additional cost: ~$20.60/month
```

**Break-even**: 2-3 clients make TGW approach cost-effective.

### Additional Savings

1. **S3 Intelligent-Tiering**: Automatic cost optimization for logs
2. **Spot Instances**: Optional for non-production EKS nodes
3. **EBS gp3**: Better price/performance than gp2
4. **Lifecycle Policies**: Auto-archive old observability data

---

## Scalability Considerations

### Current Limits

| Resource | Limit | Usage (3 clients) | Headroom |
|----------|-------|-------------------|----------|
| VPCs per region | 100 | 4 (1 egress + 3 client) | 96 |
| TGW attachments | 5,000 | 4 | 4,996 |
| CIDR allocations | 255 | 3 | 252 |
| EKS clusters/region | 100 | 3 | 97 |

### Growth Path

**Phase 1** (0-10 clients):
- Current architecture sufficient
- Monitor NAT Gateway bandwidth
- Optimize data transfer costs

**Phase 2** (10-50 clients):
- Consider additional Egress VPCs per region
- Implement TGW route table segmentation
- Add cross-region replication

**Phase 3** (50+ clients):
- Multi-region deployment
- Dedicated egress per region
- Advanced TGW routing with peering

---

## Security Architecture

### Network Isolation

1. **VPC-level isolation**: Separate VPCs per client
2. **Security groups**: Least-privilege per workload
3. **NACLs**: Additional layer (optional)
4. **VPC Flow Logs**: Network monitoring

### Data Protection

1. **Encryption at rest**: KMS for EBS, S3, RDS
2. **Encryption in transit**: TLS for all services
3. **State file encryption**: KMS for Terraform state
4. **Secrets management**: AWS Secrets Manager

### Access Control

1. **RBAC**: Kubernetes role-based access
2. **IAM**: Service-specific roles
3. **Tag-Based Access Control**: Per-client resource filtering
4. **VPN**: Secure on-premises connectivity

---

## High Availability

### Multi-AZ Design

- **NAT Gateways**: 2 (one per AZ)
- **EKS nodes**: Spread across 2 AZs
- **Databases**: Master + replica in different AZs
- **Load balancers**: ALB/NLB across AZs

### Failure Scenarios

| Failure | Impact | Recovery |
|---------|--------|----------|
| Single NAT Gateway | 50% capacity | Automatic (multi-AZ) |
| AZ outage | 50% capacity | Automatic rebalancing |
| TGW attachment failure | Client isolated | Manual reattachment |
| EKS node failure | Pod rescheduled | Automatic (autoscaler) |

---

## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Deploy your first client
- [Networking Guide](NETWORKING.md) - Detailed routing and VPN
- [Cost Optimization](COST-OPTIMIZATION.md) - FinOps best practices
- [Security Guide](SECURITY.md) - Hardening and compliance

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
