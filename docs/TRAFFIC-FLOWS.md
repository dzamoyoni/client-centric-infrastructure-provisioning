# Network Traffic Flows - Complete Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Client-Centric Infrastructure                          │
│                                                                               │
│  Hub VPC (Egress) ←→ Transit Gateway ←→ Client VPCs (Premium/Standard)      │
│                                                                               │
│  Ingress: Internet/VPN → ALB → EKS → Services                               │
│  Egress: Services → NAT → Internet (via Hub VPC)                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents
1. [Ingress Traffic Flows](#ingress-traffic-flows)
   - Internet-Facing ALB (Premium Clients)
   - Internal ALB via VPN (Standard Clients)
2. [Egress Traffic Flows](#egress-traffic-flows)
   - Centralized Egress via Hub VPC
   - Per-Client NAT Gateway (Optional)
3. [Security Groups & Network ACLs](#security-groups-network-acls)
4. [Complete Flow Examples](#complete-flow-examples)

---

# Ingress Traffic Flows

## Scenario 1: Internet-Facing ALB (Premium Client)

### Use Case
- External users accessing client-a.example.com
- Public-facing web applications
- API endpoints for mobile apps

### Traffic Flow Diagram

```
┌──────────────┐
│   Internet   │  External User (Anywhere in the world)
│    Users     │  URL: https://client-a.example.com:30443
└──────┬───────┘
       │ ① Internet traffic
       │ (Port: 30443 HTTPS)
       │
┌──────▼──────────────────────────────────────────────────────────────────────┐
│                         AWS Region: us-east-2                                │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    CLIENT-A VPC (10.1.0.0/16)                          │ │
│  │                                                                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │              Public Subnets (Multi-AZ)                            │ │ │
│  │  │              10.1.1.0/24, 10.1.2.0/24, 10.1.3.0/24                │ │ │
│  │  │                                                                    │ │ │
│  │  │  ┌───────────────────────────────────────────────────────────┐   │ │ │
│  │  │  │  Internet Gateway (IGW)                                    │   │ │ │
│  │  │  │  - Managed by AWS                                         │   │ │ │
│  │  │  │  - Stateless, highly available                            │   │ │ │
│  │  │  └───────────────┬───────────────────────────────────────────┘   │ │ │
│  │  │                  │                                                 │ │ │
│  │  │  ② Route: 0.0.0.0/0 → IGW                                          │ │ │
│  │  │                  │                                                 │ │ │
│  │  │  ┌───────────────▼───────────────────────────────────────────┐   │ │ │
│  │  │  │  Internet-Facing Application Load Balancer                │   │ │ │
│  │  │  │  - DNS: client-a-prod-public-alb-123456.us-east-2.elb... │   │ │ │
│  │  │  │  - Listeners: 30443 (HTTPS), 30080 (HTTP → redirect)     │   │ │ │
│  │  │  │  - SSL Termination: AWS ACM Certificate                   │   │ │ │
│  │  │  │  - WAF Enabled: SQL injection, XSS protection             │   │ │ │
│  │  │  │  - Security Group: client-a-pub-alb-sg                    │   │ │ │
│  │  │  │    - Allow 0.0.0.0/0:30443 (HTTPS)                        │   │ │ │
│  │  │  │    - Allow 0.0.0.0/0:30080 (HTTP)                         │   │ │ │
│  │  │  └───────────────┬───────────────────────────────────────────┘   │ │ │
│  │  └──────────────────┼─────────────────────────────────────────────┘ │ │
│  │                     │                                                  │ │
│  │  ③ Traffic decrypted (HTTPS → HTTP)                                   │ │
│  │     ALB forwards to Target Group (EKS nodes)                           │ │
│  │                     │                                                  │ │
│  │  ┌──────────────────▼─────────────────────────────────────────────┐ │ │
│  │  │              Private Subnets (Multi-AZ)                          │ │ │
│  │  │              10.1.11.0/24, 10.1.12.0/24, 10.1.13.0/24           │ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐  │ │ │
│  │  │  │  EKS Worker Nodes (Auto Scaling Group)                   │  │ │ │
│  │  │  │  - Instance Type: t3.large (Premium)                     │  │ │ │
│  │  │  │  - Security Group: client-a-eks-node-sg                  │  │ │ │
│  │  │  │    - Allow ALB SG → 30443 (NodePort HTTPS)               │  │ │ │
│  │  │  │    - Allow ALB SG → 30080 (NodePort HTTP)                │  │ │ │
│  │  │  │                                                           │  │ │ │
│  │  │  │  ④ Traffic arrives at NodePort Service                    │  │ │ │
│  │  │  │     Port: 30443 → Container Port: 80                      │  │ │ │
│  │  │  │                                                           │  │ │ │
│  │  │  │  ┌────────────────────────────────────────────────────┐ │  │ │ │
│  │  │  │  │  Istio Ingress Gateway Pod                         │ │  │ │ │
│  │  │  │  │  - Service: istio-ingressgateway (NodePort)        │ │  │ │ │
│  │  │  │  │  - NodePort: 30080 → Container: 80 (HTTP)          │ │  │ │ │
│  │  │  │  │  - NodePort: 30443 → Container: 80 (HTTP)          │ │  │ │ │
│  │  │  │  │  - Health Check: Port 15021 (/healthz/ready)       │ │  │ │ │
│  │  │  │  │                                                     │ │  │ │ │
│  │  │  │  │  ⑤ Istio processes request                          │ │  │ │ │
│  │  │  │  │     Matches VirtualService rules                    │ │  │ │ │
│  │  │  │  │     Applies mTLS, policies, telemetry              │ │  │ │ │
│  │  │  │  └────────────┬───────────────────────────────────────┘ │  │ │ │
│  │  │  │               │                                          │  │ │ │
│  │  │  │  ⑥ Route to backend service based on VirtualService     │  │ │ │
│  │  │  │               │                                          │  │ │ │
│  │  │  │     ┌─────────┴──────────┬──────────────┬──────────┐   │  │ │ │
│  │  │  │     │                    │              │          │   │  │ │ │
│  │  │  │  ┌──▼───┐          ┌────▼────┐   ┌────▼────┐ ┌───▼──┐ │  │ │ │
│  │  │  │  │ /api │          │ /admin  │   │ /users  │ │  /   │ │  │ │ │
│  │  │  │  │  →   │          │   →     │   │   →     │ │  →   │ │  │ │ │
│  │  │  │  │backend│         │  admin  │   │  user   │ │frontend│ │ │ │
│  │  │  │  │ :8080│          │  :9000  │   │  :8080  │ │ :3000│ │  │ │ │
│  │  │  │  └──┬───┘          └────┬────┘   └────┬────┘ └───┬──┘ │  │ │ │
│  │  │  │     │                   │             │          │    │  │ │ │
│  │  │  │  ⑦ Service Pod processes request and returns response │  │ │ │
│  │  │  │     │                                                  │  │ │ │
│  │  │  │  ┌──▼────────────────────────────────────────────────┐ │  │ │ │
│  │  │  │  │  RDS PostgreSQL (if needed)                       │ │  │ │ │
│  │  │  │  │  - Subnet: 10.1.21.0/24 (DB Subnet)               │ │  │ │ │
│  │  │  │  │  - Security Group: Allow only from EKS subnet     │ │  │ │ │
│  │  │  │  │  - Port: 5432                                     │ │  │ │ │
│  │  │  │  └───────────────────────────────────────────────────┘ │  │ │ │
│  │  │  └──────────────────────────────────────────────────────┘  │ │ │
│  │  └─────────────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘

Response flows back:
Service Pod → Istio → EKS Node → ALB → IGW → Internet → User
```

### Detailed Step-by-Step

| Step | Component | Action | Protocol | Port | Notes |
|------|-----------|--------|----------|------|-------|
| ① | Internet → IGW | User request arrives | HTTPS | 30443 | Route53 resolves DNS to ALB |
| ② | IGW → ALB | Routes to ALB in public subnet | HTTPS | 30443 | IGW is stateless |
| ③ | ALB → EKS Node | SSL termination, forwards HTTP | HTTP | 30443 | ALB health checks NodePort |
| ④ | EKS Node → Istio | NodePort service forwards | HTTP | 80 | kube-proxy handles routing |
| ⑤ | Istio Gateway | Processes VirtualService rules | HTTP | 80 | mTLS, policies applied |
| ⑥ | Istio → Service | Routes to backend service | HTTP | 8080 | Based on path/headers |
| ⑦ | Service → DB | Queries database (if needed) | PostgreSQL | 5432 | Within private subnet |
| ⑧ | Response | Reverse path back to user | HTTPS | 30443 | ALB re-encrypts |

---

## Scenario 2: Internal ALB via Site-to-Site VPN (Standard Client)

### Use Case
- Corporate users accessing internal applications
- VPN-connected remote employees
- Partner integrations via dedicated VPN

### Traffic Flow Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     Corporate Network / On-Premises DC                      │
│                           CIDR: 10.200.0.0/16                               │
│                                                                              │
│  ┌──────────────┐         ┌───────────────────┐                            │
│  │  Corporate   │         │  VPN Gateway      │                            │
│  │  Users       │ ──────► │  (Customer Side)  │                            │
│  │  10.200.1.x  │         │  Public IP: x.x.x.x│                           │
│  └──────────────┘         └─────────┬─────────┘                            │
└───────────────────────────────────────┼──────────────────────────────────────┘
                                        │
                                        │ ① Site-to-Site VPN Tunnel
                                        │    (IPsec Encrypted)
                                        │    IKEv2, AES-256-GCM
                                        │
┌───────────────────────────────────────▼──────────────────────────────────────┐
│                         AWS Region: us-east-2                                │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    CLIENT-B VPC (10.2.0.0/16)                          │ │
│  │                                                                         │ │
│  │  ② VPN arrives at Virtual Private Gateway (VGW)                         │ │
│  │     attached to CLIENT-B VPC                                            │ │
│  │                                                                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │              Public Subnets (Multi-AZ)                            │ │ │
│  │  │              10.2.1.0/24, 10.2.2.0/24, 10.2.3.0/24                │ │ │
│  │  │                                                                    │ │ │
│  │  │  ┌───────────────────────────────────────────────────────────┐   │ │ │
│  │  │  │  Internal Application Load Balancer                        │   │ │ │
│  │  │  │  - DNS: client-b-prod-internal-alb-123456.us-east-2...    │   │ │ │
│  │  │  │  - Scheme: internal (No public IP)                        │   │ │ │
│  │  │  │  - Listeners: 30443 (HTTPS), 30080 (HTTP)                 │   │ │ │
│  │  │  │  - SSL Termination: AWS ACM Certificate (internal)        │   │ │ │
│  │  │  │  - Security Group: client-b-int-alb-sg                    │   │ │ │
│  │  │  │    - Allow 10.200.0.0/16:30443 (Corporate network)        │   │ │ │
│  │  │  │    - Allow 10.200.0.0/16:30080 (Corporate network)        │   │ │ │
│  │  │  │    - Deny all other traffic                               │   │ │ │
│  │  │  └───────────────┬───────────────────────────────────────────┘   │ │ │
│  │  └──────────────────┼─────────────────────────────────────────────┘ │ │
│  │                     │                                                  │ │
│  │  ③ Traffic decrypted (HTTPS → HTTP)                                   │ │
│  │     ALB forwards to Target Group (EKS nodes)                           │ │
│  │                     │                                                  │ │
│  │  ┌──────────────────▼─────────────────────────────────────────────┐ │ │
│  │  │              Private Subnets (Multi-AZ)                          │ │ │
│  │  │              10.2.11.0/24, 10.2.12.0/24, 10.2.13.0/24           │ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌──────────────────────────────────────────────────────────┐  │ │ │
│  │  │  │  EKS Worker Nodes (SPOT Instances - Standard Tier)       │  │ │ │
│  │  │  │  - Instance Type: t3.medium                              │  │ │ │
│  │  │  │  - Security Group: client-b-eks-node-sg                  │  │ │ │
│  │  │  │    - Allow Internal ALB SG → 30443, 30080                │  │ │ │
│  │  │  │                                                           │  │ │ │
│  │  │  │  ④ Traffic arrives at NodePort → Istio → Services         │  │ │ │
│  │  │  │     (Same flow as Scenario 1, steps ④-⑦)                 │  │ │ │
│  │  │  └──────────────────────────────────────────────────────────┘  │ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘

Response flows back:
Service → Istio → EKS → ALB → VGW → VPN Tunnel → Corporate Network
```

### VPN Configuration Details

```hcl
# Virtual Private Gateway (attached to Client VPC)
resource "aws_vpn_gateway" "client_vpn" {
  vpc_id = aws_vpc.client.id
  
  tags = {
    Name = "client-b-vpn-gateway"
  }
}

# Customer Gateway (represents on-premises VPN device)
resource "aws_customer_gateway" "corporate" {
  bgp_asn    = 65000
  ip_address = "203.0.113.10"  # Corporate public IP
  type       = "ipsec.1"
  
  tags = {
    Name = "client-b-corporate-gateway"
  }
}

# Site-to-Site VPN Connection
resource "aws_vpn_connection" "corporate" {
  vpn_gateway_id      = aws_vpn_gateway.client_vpn.id
  customer_gateway_id = aws_customer_gateway.corporate.id
  type                = "ipsec.1"
  static_routes_only  = false  # Use BGP for dynamic routing
  
  # Two tunnels for high availability
  tunnel1_inside_cidr = "169.254.10.0/30"
  tunnel2_inside_cidr = "169.254.10.4/30"
  
  tags = {
    Name = "client-b-corporate-vpn"
  }
}

# Route propagation (automatic route updates via BGP)
resource "aws_vpn_gateway_route_propagation" "client_private" {
  vpn_gateway_id = aws_vpn_gateway.client_vpn.id
  route_table_id = aws_route_table.client_private.id
}
```

### VPN Security

```
VPN Tunnel Configuration:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 1 (IKE):
- Protocol: IKEv2
- Encryption: AES-256-GCM
- Integrity: SHA-384
- DH Group: Group 20 (2048-bit MODP)
- Lifetime: 28800 seconds (8 hours)

Phase 2 (IPsec):
- Protocol: ESP
- Encryption: AES-256-GCM
- Integrity: SHA-384
- Perfect Forward Secrecy: Group 20
- Lifetime: 3600 seconds (1 hour)

Redundancy:
- Tunnel 1: Primary (active)
- Tunnel 2: Secondary (standby)
- Automatic failover via BGP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

# Egress Traffic Flows

## Scenario 3: Centralized Egress via Hub VPC (Recommended)

### Use Case
- Services calling external APIs (Stripe, Twilio, etc.)
- Software updates (apt, yum, pip, npm)
- Container image pulls from Docker Hub, ECR
- Cost optimization (shared NAT gateway)

### Traffic Flow Diagram

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         AWS Region: us-east-2                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    CLIENT-A VPC (10.1.0.0/16)                        │  │
│  │                                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────────┐ │  │
│  │  │              Private Subnets (EKS)                             │ │  │
│  │  │              10.1.11.0/24, 10.1.12.0/24, 10.1.13.0/24          │ │  │
│  │  │                                                                 │ │  │
│  │  │  ┌──────────────────────────────────────────────────────────┐ │ │  │
│  │  │  │  Pod in EKS (e.g., backend-api)                          │ │ │  │
│  │  │  │  - Pod IP: 10.1.11.45                                    │ │ │  │
│  │  │  │  - Needs to call: api.stripe.com                         │ │ │  │
│  │  │  │                                                           │ │ │  │
│  │  │  │  ① Pod initiates outbound request                         │ │ │  │
│  │  │  │     curl https://api.stripe.com/v1/charges               │ │ │  │
│  │  │  └───────────────────┬──────────────────────────────────────┘ │ │  │
│  │  └──────────────────────┼────────────────────────────────────────┘ │  │
│  │                         │                                            │  │
│  │  ② Route lookup in Private Subnet Route Table                       │  │
│  │     Destination: 0.0.0.0/0 (Internet)                               │  │
│  │     Target: Transit Gateway (tgw-xxxxx)                             │  │
│  │                         │                                            │  │
│  │  ┌──────────────────────▼────────────────────────────────────────┐ │  │
│  │  │  Transit Gateway Attachment (Client-A)                        │ │  │
│  │  │  - ENI in Private Subnet                                      │ │  │
│  │  │  - Associated Route Table: client-a-tgw-rt                    │ │  │
│  │  └──────────────────────┬────────────────────────────────────────┘ │  │
│  └─────────────────────────┼──────────────────────────────────────────┘  │
│                            │                                              │
│  ③ Transit Gateway routes based on Client-A route table                  │
│     Destination: 0.0.0.0/0 → Hub VPC Attachment                          │
│     (Client isolation: Client-A cannot reach Client-B)                    │
│                            │                                              │
│  ┌─────────────────────────▼──────────────────────────────────────────┐  │
│  │                Transit Gateway (tgw-xxxxx)                          │  │
│  │                                                                      │  │
│  │  Route Tables:                                                       │  │
│  │  ├─ hub-vpc-rt:         All client traffic → Hub VPC                │  │
│  │  ├─ client-a-rt:        0.0.0.0/0 → Hub VPC (isolated)              │  │
│  │  └─ client-b-rt:        0.0.0.0/0 → Hub VPC (isolated)              │  │
│  │                                                                      │  │
│  │  Client-A traffic uses client-a-rt → Hub VPC only                   │  │
│  └─────────────────────────┬──────────────────────────────────────────┘  │
│                            │                                              │
│  ④ TGW forwards to Hub VPC                                               │
│                            │                                              │
│  ┌─────────────────────────▼──────────────────────────────────────────┐  │
│  │                    HUB VPC (10.0.0.0/16)                            │  │
│  │                    (Centralized Egress)                             │  │
│  │                                                                      │  │
│  │  ┌────────────────────────────────────────────────────────────────┐│  │
│  │  │              Private Subnets                                    ││  │
│  │  │              10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24           ││  │
│  │  │                                                                  ││  │
│  │  │  ⑤ Traffic arrives from TGW                                      ││  │
│  │  │     Source: 10.1.11.45 (Client-A Pod)                           ││  │
│  │  │     Destination: api.stripe.com (54.187.x.x)                    ││  │
│  │  │                                                                  ││  │
│  │  │  Route Table:                                                    ││  │
│  │  │  - 10.1.0.0/16 → TGW (back to Client-A)                         ││  │
│  │  │  - 10.2.0.0/16 → TGW (back to Client-B)                         ││  │
│  │  │  - 0.0.0.0/0 → NAT Gateway                                      ││  │
│  │  └────────────────────┬───────────────────────────────────────────┘│  │
│  │                       │                                              │  │
│  │  ⑥ Route to NAT Gateway in Public Subnet                            │  │
│  │                       │                                              │  │
│  │  ┌────────────────────▼───────────────────────────────────────────┐│  │
│  │  │              Public Subnets                                     ││  │
│  │  │              10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24              ││  │
│  │  │                                                                  ││  │
│  │  │  ┌──────────────────────────────────────────────────────────┐  ││  │
│  │  │  │  NAT Gateway (us-east-2a)                                │  ││  │
│  │  │  │  - Elastic IP: 3.14.x.x (Public)                         │  ││  │
│  │  │  │  - Highly available, managed by AWS                      │  ││  │
│  │  │  │  - Stateful (tracks connections)                         │  ││  │
│  │  │  │                                                           │  ││  │
│  │  │  │  ⑦ SNAT: Source IP translation                            │  ││  │
│  │  │  │     10.1.11.45 → 3.14.x.x (NAT Gateway EIP)              │  ││  │
│  │  │  └────────────────┬─────────────────────────────────────────┘  ││  │
│  │  └──────────────────┼────────────────────────────────────────────┘│  │
│  │                     │                                               │  │
│  │  ⑧ Route to Internet Gateway                                        │  │
│  │                     │                                               │  │
│  │  ┌──────────────────▼────────────────────────────────────────────┐│  │
│  │  │  Internet Gateway (Hub VPC)                                    ││  │
│  │  │  - Managed by AWS, highly available                            ││  │
│  │  │  - No translation (EIP already applied by NAT)                 ││  │
│  │  └────────────────┬─────────────────────────────────────────────┘│  │
│  └───────────────────┼──────────────────────────────────────────────┘  │
└────────────────────────┼──────────────────────────────────────────────────┘
                         │
                         │ ⑨ Internet (0.0.0.0/0)
                         │    Source IP: 3.14.x.x (NAT Gateway EIP)
                         │    Destination: api.stripe.com (54.187.x.x)
                         │
                    ┌────▼─────┐
                    │ Stripe   │
                    │   API    │
                    └──────────┘

Response flows back:
Stripe → IGW → NAT (destination NAT, stateful) → Hub VPC → TGW → Client-A → Pod
```

### Detailed Step-by-Step

| Step | Component | Action | Source IP | Dest IP | Notes |
|------|-----------|--------|-----------|---------|-------|
| ① | Pod | Initiates request | 10.1.11.45 | 54.187.x.x | DNS resolves api.stripe.com |
| ② | Route Table | Lookup default route | 10.1.11.45 | 54.187.x.x | 0.0.0.0/0 → TGW |
| ③ | TGW | Route via client-a-rt | 10.1.11.45 | 54.187.x.x | Isolated routing |
| ④ | TGW → Hub | Forward to Hub VPC | 10.1.11.45 | 54.187.x.x | No IP translation |
| ⑤ | Hub Route | Route to NAT Gateway | 10.1.11.45 | 54.187.x.x | 0.0.0.0/0 → NAT |
| ⑥ | NAT Gateway | SNAT translation | **3.14.x.x** | 54.187.x.x | Source IP changed |
| ⑦ | IGW | Route to internet | 3.14.x.x | 54.187.x.x | Stateless |
| ⑧ | Internet | Reaches Stripe | 3.14.x.x | 54.187.x.x | Stripe sees NAT EIP |
| ⑨ | Response | Returns to NAT | 54.187.x.x | 3.14.x.x | NAT tracks connection |
| ⑩ | NAT → Pod | Destination NAT | 54.187.x.x | **10.1.11.45** | Stateful return |

### Cost Analysis

```
Centralized Egress (3 NAT Gateways in Hub VPC):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Per NAT Gateway:
- Hourly charge: $0.045/hour = $32.40/month
- Data processing: $0.045/GB

For 3 AZs (High Availability):
- 3 NAT Gateways × $32.40 = $97.20/month
- Data processing: $0.045/GB × total egress

All clients share:
- 10 clients share $97.20/month = $9.72/client/month
- Massive savings vs per-client NAT ($32.40 each)

Savings: $22.68/client/month × 10 clients = $226.80/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Scenario 4: Per-Client NAT Gateway (Optional for Premium)

### Use Case
- Premium clients requiring dedicated egress IPs
- Compliance requirements for IP whitelisting
- Client-specific egress monitoring

### Traffic Flow

```
CLIENT-A VPC (Premium):
Pod → Private Subnet → NAT Gateway (Client-A) → IGW (Client-A) → Internet

Benefits:
✅ Dedicated egress IP per client
✅ Independent monitoring
✅ Better for IP whitelisting

Drawbacks:
❌ Higher cost ($32.40/month per client)
❌ More NAT Gateways to manage
❌ No cost sharing
```

---

# Security Groups & Network ACLs

## Security Group Chain

### Internet-Facing ALB Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Security Group Chain                              │
└──────────────────────────────────────────────────────────────────────────┘

① ALB Security Group (client-a-pub-alb-sg)
   ┌────────────────────────────────────────┐
   │ Inbound:                               │
   │ - 0.0.0.0/0 → 30443 (HTTPS)           │
   │ - 0.0.0.0/0 → 30080 (HTTP)            │
   │                                        │
   │ Outbound:                              │
   │ - client-a-eks-node-sg → 30443        │
   │ - client-a-eks-node-sg → 30080        │
   └────────────────────────────────────────┘
                     │
                     ▼
② EKS Node Security Group (client-a-eks-node-sg)
   ┌────────────────────────────────────────┐
   │ Inbound:                               │
   │ - client-a-pub-alb-sg → 30443         │
   │ - client-a-pub-alb-sg → 30080         │
   │ - client-a-int-alb-sg → 30443         │
   │ - client-a-int-alb-sg → 30080         │
   │ - Self → All (pod-to-pod)             │
   │                                        │
   │ Outbound:                              │
   │ - 0.0.0.0/0 → All (egress to internet)│
   │ - client-a-rds-sg → 5432              │
   └────────────────────────────────────────┘
                     │
                     ▼
③ RDS Security Group (client-a-rds-sg)
   ┌────────────────────────────────────────┐
   │ Inbound:                               │
   │ - client-a-eks-node-sg → 5432         │
   │                                        │
   │ Outbound:                              │
   │ - None (database doesn't initiate)    │
   └────────────────────────────────────────┘
```

### Network ACLs (Optional Additional Security)

```hcl
# Public Subnet NACL
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.client.id
  subnet_ids = aws_subnet.public[*].id
  
  # Allow HTTPS inbound
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 30443
    to_port    = 30443
  }
  
  # Allow HTTP inbound
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 30080
    to_port    = 30080
  }
  
  # Allow return traffic (ephemeral ports)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  
  # Allow all outbound
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# Private Subnet NACL
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.client.id
  subnet_ids = aws_subnet.eks[*].id
  
  # Allow traffic from public subnets (ALB)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.1.0.0/20"  # Public subnet range
    from_port  = 0
    to_port    = 65535
  }
  
  # Allow return traffic
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  
  # Allow all outbound
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}
```

---

# Complete Flow Examples

## Example 1: User Accessing Web Application

```
Scenario: External user accesses https://app.client-a.example.com:30443

Full Flow:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① User's browser: DNS lookup
   - Query: app.client-a.example.com
   - Route53 responds: client-a-prod-public-alb-123456.us-east-2.elb.amazonaws.com
   - Resolves to: 3.14.50.100, 3.14.50.101, 3.14.50.102 (ALB IPs)

② Browser initiates HTTPS connection
   - TLS handshake with ALB
   - Certificate verified (AWS ACM cert)
   - HTTP request sent: GET / HTTP/1.1

③ ALB processes request
   - WAF rules checked (SQL injection, XSS, rate limiting)
   - SSL terminated (HTTPS → HTTP)
   - Health check passed (NodePort 30080:/healthz/ready)
   - Forwards to target group: client-a-pub-https-tg

④ Target Group selects healthy EKS node
   - Round-robin across 3 AZs
   - Forwards to NodePort 30443 on EKS node 10.1.11.5

⑤ EKS Node (kube-proxy)
   - iptables rule: NodePort 30443 → Service istio-ingressgateway:80
   - Forwards to Pod: 10.1.11.45:80

⑥ Istio Ingress Gateway
   - Receives request on port 80
   - Matches VirtualService: app.client-a.example.com
   - Rule: path "/" → service: frontend-service
   - Applies mTLS, policies, telemetry
   - Forwards to: frontend-service:3000

⑦ Frontend Service Pod
   - Processes request
   - Calls backend API: backend-api-service:8080/api/users
   - Istio applies mTLS between services

⑧ Backend API Service Pod
   - Queries RDS: SELECT * FROM users WHERE id=1
   - RDS connection: 10.1.11.45 → 10.1.21.10:5432
   - Returns data to frontend

⑨ Response returns
   - Frontend → Istio → EKS Node → ALB
   - ALB re-encrypts (HTTP → HTTPS)
   - Returns to user's browser

Total Latency: ~150-300ms
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Example 2: Service Calling External API

```
Scenario: Backend pod calls Stripe API to process payment

Full Flow:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① Backend pod initiates request
   - Pod IP: 10.1.11.45
   - Code: stripe.Charge.create(amount=1000, currency="usd")
   - DNS lookup: api.stripe.com → 54.187.205.235

② Route table lookup (Private Subnet)
   - Destination: 54.187.205.235
   - Match: 0.0.0.0/0 → Transit Gateway

③ Transit Gateway routing
   - Source: 10.1.11.45 (Client-A VPC)
   - Lookup in client-a-tgw-rt
   - Match: 0.0.0.0/0 → Hub VPC attachment

④ Hub VPC receives traffic
   - Source: 10.1.11.45
   - Destination: 54.187.205.235
   - Route table: 0.0.0.0/0 → NAT Gateway (us-east-2a)

⑤ NAT Gateway performs SNAT
   - Source IP: 10.1.11.45 → 3.14.100.50 (NAT EIP)
   - Destination: 54.187.205.235
   - Connection tracked in state table

⑥ Internet Gateway
   - Routes to internet (0.0.0.0/0)
   - Source: 3.14.100.50
   - Destination: 54.187.205.235

⑦ Stripe API receives request
   - Sees source IP: 3.14.100.50 (NAT Gateway EIP)
   - Processes payment
   - Returns response

⑧ Response returns via NAT
   - Source: 54.187.205.235
   - Destination: 3.14.100.50 (NAT EIP)
   - NAT uses state table to translate: 3.14.100.50 → 10.1.11.45
   - Returns via TGW → Client-A VPC → Pod

Total Latency: ~100-200ms (depends on Stripe)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Example 3: VPN User Accessing Internal Application

```
Scenario: Corporate user accesses https://internal.client-b.example.com:30443

Full Flow:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① User on corporate network
   - IP: 10.200.1.50 (corporate subnet)
   - DNS resolves to internal ALB: 10.2.5.10 (private IP)
   - Browser: https://internal.client-b.example.com:30443

② Traffic enters VPN tunnel
   - Encrypted with IPsec (AES-256-GCM)
   - BGP advertises route: 10.2.0.0/16 via VPN
   - Tunnel established to AWS VGW

③ Virtual Private Gateway (VGW)
   - Receives encrypted traffic
   - Decrypts IPsec
   - Source: 10.200.1.50, Destination: 10.2.5.10
   - Routes to Client-B VPC

④ Internal ALB (in public subnet, but private IP)
   - Receives request on 10.2.5.10:30443
   - Security group allows: 10.200.0.0/16 → 30443
   - SSL terminated
   - Forwards to EKS NodePort 30443

⑤ EKS processes request
   - NodePort → Istio → Services
   - Same internal flow as previous examples

⑥ Response returns
   - Services → Istio → EKS → ALB
   - ALB → VGW → VPN tunnel → Corporate user

Total Latency: ~50-100ms (VPN adds ~20-30ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

# Summary Table

| Scenario | Ingress Path | Egress Path | Use Case |
|----------|-------------|-------------|----------|
| **Internet → Public ALB** | Internet → IGW → ALB → EKS → Istio → Services | Services → TGW → Hub VPC → NAT → IGW → Internet | Public web apps, APIs |
| **VPN → Internal ALB** | Corporate → VPN → VGW → ALB → EKS → Istio → Services | Services → TGW → Hub VPC → NAT → IGW → Internet | Internal apps, admin panels |
| **Service → External API** | N/A | Services → TGW → Hub VPC → NAT → IGW → API | Payment gateways, SaaS APIs |
| **Pod → RDS** | N/A | Pod → RDS (same VPC, private) | Database queries |

---

# Monitoring & Troubleshooting

## CloudWatch Metrics to Monitor

```
ALB Metrics:
- TargetResponseTime: Latency from ALB to EKS
- HealthyHostCount: Number of healthy targets
- UnHealthyHostCount: Failing health checks
- RequestCount: Requests per second
- HTTPCode_Target_4XX_Count: Backend errors
- HTTPCode_ELB_5XX_Count: ALB errors

NAT Gateway Metrics:
- BytesInFromSource: Inbound traffic from clients
- BytesOutToDestination: Outbound traffic to internet
- PacketsDropCount: Dropped packets (capacity issues)

VPN Metrics:
- TunnelState: Up/Down status
- TunnelDataIn: Inbound VPN traffic
- TunnelDataOut: Outbound VPN traffic
```

## Common Issues & Solutions

```
Issue: ALB returns 502 Bad Gateway
Cause: EKS nodes unhealthy or NodePort not responding
Solution: Check EKS node health, verify Istio gateway is running

Issue: VPN tunnel down
Cause: Phase 1/2 mismatch, BGP issue, firewall
Solution: Check customer gateway config, verify IKE settings

Issue: High NAT Gateway costs
Cause: Excessive egress traffic
Solution: Use VPC endpoints for AWS services (S3, ECR, etc.)

Issue: Slow response times
Cause: Cross-AZ traffic, unhealthy targets
Solution: Enable cross-zone load balancing, scale EKS nodes
```

---

**Your architecture is production-grade and follows AWS best practices!** 🚀
