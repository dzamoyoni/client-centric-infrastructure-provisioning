# Networking Guide

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Transit Gateway Architecture

### Hub-and-Spoke Model

```
                          Internet
                             │
                    ┌────────┴────────┐
                    │   Egress VPC    │  ← Hub (NAT Gateways)
                    │  10.255.0.0/16  │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │ Transit Gateway │  ← Routing Hub
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────┴─────┐    ┌────┴────┐    ┌─────┴─────┐
      │ Client A  │    │Client B │    │ Client C  │  ← Spokes
      │(NAT-less) │    │(NAT-less)│    │(NAT-less) │
      └───────────┘    └─────────┘    └───────────┘
```

---

## Traffic Flows

### Internet-Bound Traffic

```
Client Pod → Private Subnet → Transit Gateway → Egress VPC → NAT → Internet
```

**Route Table (Client VPC)**:
```
Destination      Target
10.100.0.0/16    local
0.0.0.0/0        tgw-xxxxx  (Transit Gateway)
```

**Route Table (Egress VPC)**:
```
Destination      Target
10.255.0.0/16    local
10.100.0.0/16    tgw-xxxxx  (to Client A)
10.101.0.0/16    tgw-xxxxx  (to Client B)
0.0.0.0/0        nat-xxxxx  (NAT Gateway)
```

---

## VPN Integration

### Architecture

VPN Gateway attached to client VPC coexists with Transit Gateway routing.

```
On-Premises                         AWS Cloud
┌──────────────┐                   ┌──────────────┐
│Customer GW   │◄─────IPSec────────┤VPN Gateway   │
│192.168.0.1   │                   │(Client VPC)  │
└──────────────┘                   └──────┬───────┘
                                          │
                                    ┌─────┴──────┐
                                    │Client VPC  │
                                    │Route Table │
                                    └────────────┘
                                    Routes:
                                    192.168.0.0/24 → VPN GW (specific)
                                    0.0.0.0/0 → TGW (default)
```

### Routing Behavior

**Longest-prefix match** ensures correct routing:
- On-premises: `192.168.0.0/24` → VPN Gateway (wins)
- Internet: `0.0.0.0/0` → Transit Gateway (fallback)

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

---

## Security Groups

### EKS Node Security Group
- **Inbound**: From ALB security group
- **Outbound**: All traffic (via TGW)

### Database Security Group
- **Inbound**: From EKS security group on ports 5432, 5433
- **Outbound**: None

### ALB Security Group
- **Inbound**: HTTPS (443) from internet
- **Outbound**: To EKS security group

---

## VPC Flow Logs

Enabled for all VPCs, stored in CloudWatch.

**Query for rejected traffic**:
```bash
aws logs start-query \
  --log-group-name "/aws/vpc/flow-logs" \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, srcAddr, dstAddr, action | filter action = "REJECT"'
```

---

## DNS Architecture

### Route53 Zone Structure

```
xyz.com (parent zone)
├── client-a.xyz.com (delegated)
├── client-b.xyz.com (delegated)
└── client-c.xyz.com (delegated)
```

### ExternalDNS Integration

Automatically creates DNS records for Kubernetes services:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.client-a.xyz.com
spec:
  type: LoadBalancer
```

---

## Troubleshooting

### No Internet Connectivity

```bash
# Check TGW attachment
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=vpc-id,Values={vpc-id}"

# Verify routes
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values={vpc-id}"

# Test from pod
kubectl run test --image=nicolaka/netshoot -it --rm -- bash
curl -I https://www.google.com
```

### VPN Not Working

```bash
# Check VPN status
aws ec2 describe-vpn-connections

# Check route propagation
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values={vpc-id}"

# Verify VPN tunnel status
aws ec2 describe-vpn-connections \
  --vpn-connection-ids {vpn-id} \
  | jq '.VpnConnections[].VgwTelemetry'
```

---

## Related Documentation

- [Architecture](ARCHITECTURE.md) - Design overview
- [Getting Started](GETTING-STARTED.md) - Deployment
- [Troubleshooting](TROUBLESHOOTING.md) - Network issues

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
