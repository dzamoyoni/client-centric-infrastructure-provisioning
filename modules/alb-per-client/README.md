# ALB Per-Client Module

Enterprise-grade Application Load Balancer module for multi-tenant Kubernetes infrastructure with Istio service mesh integration.

## Overview

This module provisions AWS Application Load Balancers (ALBs) for per-client EKS clusters with support for:
- **Dual ALB deployment** (internet-facing + internal)
- **Custom port mapping** (ALB 30443/30080 → NodePort → Istio 80)
- **SSL/TLS termination** with AWS Certificate Manager
- **WAF integration** for public-facing ALBs
- **Production-grade security** with least-privilege security groups
- **High availability** across multiple availability zones

## Architecture

### Traffic Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          External Traffic                                │
│                    (Internet or VPN/Corporate)                           │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                          │ HTTPS (30443) / HTTP (30080)
                          │
┌─────────────────────────▼───────────────────────────────────────────────┐
│                    AWS Application Load Balancer                         │
│  - SSL/TLS Termination (ACM Certificate)                                │
│  - Layer 7 Load Balancing                                               │
│  - WAF Protection (Optional)                                            │
│  - Health Checks                                                        │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                          │ HTTP (NodePort 30443/30080)
                          │
┌─────────────────────────▼───────────────────────────────────────────────┐
│                       EKS Worker Nodes                                   │
│  - NodePort Service                                                     │
│  - Security Group Rules                                                 │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
                          │ HTTP (Port 80)
                          │
┌─────────────────────────▼───────────────────────────────────────────────┐
│                  Istio Ingress Gateway                                   │
│  - Service Mesh Entry Point                                             │
│  - mTLS Internal Traffic                                                │
│  - Advanced Routing (VirtualServices)                                   │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
     ┌────▼────┐     ┌────▼────┐     ┌────▼────┐
     │ Service │     │ Service │     │ Service │
     │    A    │     │    B    │     │    C    │
     └─────────┘     └─────────┘     └─────────┘
```

### Key Design Principles

1. **ALB handles external ingress** - SSL termination, WAF, Layer 7 load balancing
2. **Istio handles internal routing** - Service mesh, mTLS, advanced traffic management
3. **Separation of concerns** - ALB for external, Istio VirtualServices for internal
4. **Client isolation** - Each client has dedicated ALB(s) and networking

## Routing Responsibilities

### ALB Responsibilities (External)
- SSL/TLS termination (HTTPS → HTTP)
- DDoS protection (AWS Shield)
- WAF rules (SQL injection, XSS, etc.)
- Health checks to Istio gateway
- Layer 7 load balancing across AZs
- Access logging

### Istio Responsibilities (Internal)
- **VirtualServices** - Custom routing rules, path-based routing, header-based routing
- **DestinationRules** - Load balancing, circuit breaking, connection pooling
- **Gateways** - Internal traffic management
- mTLS between services
- Observability (metrics, traces, logs)

### Example: Custom Routing with Istio VirtualServices

```yaml
# ALB forwards ALL traffic to Istio on port 80
# Istio VirtualService handles the routing logic

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app-routes
spec:
  hosts:
  - "myapp.client-a.example.com"
  gateways:
  - istio-ingressgateway
  http:
  # Route /api/* to backend service
  - match:
    - uri:
        prefix: "/api"
    route:
    - destination:
        host: backend-service
        port:
          number: 8080
  
  # Route /admin* to admin service (with auth header)
  - match:
    - uri:
        prefix: "/admin"
      headers:
        x-admin-token:
          exact: "secret-admin-token"
    route:
    - destination:
        host: admin-service
        port:
          number: 9000
  
  # Default route to frontend
  - route:
    - destination:
        host: frontend-service
        port:
          number: 3000
```

## Usage

### Basic Usage (Both ALBs)

```hcl
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  # Client identification
  client_id   = "client-a"
  environment = "production"
  
  # Network configuration
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  # ALB type: "internet-facing", "internal", or "both"
  alb_type = "both"
  
  # SSL/TLS
  ssl_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/xxx"
  
  # Access logs
  access_logs_bucket = "client-a-alb-logs-us-east-2"
  
  # Security
  allowed_cidr_blocks_internal = ["10.200.0.0/16"]  # VPN CIDR
  
  # Tags from shared-config module
  tags = module.tags.common_tags
}

# Attach ALB target groups to EKS Auto Scaling Group
resource "aws_autoscaling_attachment" "alb_targets" {
  for_each = toset(module.client_alb.target_group_arns)
  
  autoscaling_group_name = module.eks.node_group_asg_name
  lb_target_group_arn    = each.value
}
```

### Internet-Facing Only

```hcl
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  client_id   = "client-b"
  environment = "production"
  
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  alb_type                = "internet-facing"
  ssl_certificate_arn     = "arn:aws:acm:us-east-2:123456789012:certificate/yyy"
  access_logs_bucket      = "client-b-alb-logs-us-east-2"
  
  # WAF for public ALB
  waf_acl_arn = "arn:aws:wafv2:us-east-2:123456789012:regional/webacl/client-b-waf/xxx"
  
  tags = module.tags.common_tags
}
```

### Internal Only (VPN Access)

```hcl
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  client_id   = "client-c"
  environment = "production"
  
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  alb_type                         = "internal"
  ssl_certificate_arn              = "arn:aws:acm:us-east-2:123456789012:certificate/zzz"
  access_logs_bucket               = "client-c-alb-logs-us-east-2"
  allowed_cidr_blocks_internal     = ["10.200.0.0/16", "172.16.0.0/12"]
  
  # Disable deletion protection for non-production
  enable_deletion_protection = false
  
  tags = module.tags.common_tags
}
```

### Custom Port Configuration

```hcl
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  client_id   = "client-d"
  environment = "production"
  
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  alb_type            = "internet-facing"
  ssl_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/www"
  
  # Custom ports
  https_external_port = 443     # Standard HTTPS port
  http_external_port  = 80      # Standard HTTP port
  https_nodeport      = 31443   # Custom NodePort
  http_nodeport       = 31080   # Custom NodePort
  
  # Do NOT redirect HTTP to HTTPS (allow both)
  redirect_http_to_https = false
  
  tags = module.tags.common_tags
}
```

### Advanced Configuration with Sticky Sessions

```hcl
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  client_id   = "client-e"
  environment = "production"
  
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
  
  alb_type                = "both"
  ssl_certificate_arn     = "arn:aws:acm:us-east-2:123456789012:certificate/client-e"
  access_logs_bucket      = "client-e-alb-logs-us-east-2"
  
  # Enable session affinity
  enable_sticky_sessions = true
  
  # Custom health check path (must be exposed by Istio)
  health_check_path = "/health/live"
  
  # Stricter SSL policy
  ssl_policy = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  
  # Separate certificate for internal ALB
  ssl_certificate_arn_internal = "arn:aws:acm:us-east-2:123456789012:certificate/client-e-internal"
  
  tags = module.tags.common_tags
}
```

## Istio Ingress Gateway Configuration

To integrate with this ALB module, configure your Istio Ingress Gateway with NodePort:

```yaml
# istio-ingressgateway-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway
  namespace: istio-system
spec:
  type: NodePort
  selector:
    app: istio-ingressgateway
    istio: ingressgateway
  ports:
  # HTTP port (ALB sends decrypted traffic here)
  - name: http2
    port: 80
    targetPort: 8080
    nodePort: 30080  # Must match http_nodeport in module
    protocol: TCP
  
  # HTTPS port (if ALB forwards encrypted traffic)
  - name: https
    port: 443
    targetPort: 8443
    nodePort: 30443  # Must match https_nodeport in module
    protocol: TCP
  
  # Istio status port for health checks
  - name: status-port
    port: 15021
    targetPort: 15021
    nodePort: 30021
    protocol: TCP
```

### Health Check Endpoint

Ensure Istio exposes the health check path:

```yaml
# Gateway configuration
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: istio-ingressgateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

The module uses `/healthz/ready` by default, which is exposed by Istio on port 15021.

## Route53 DNS Configuration (Optional)

```hcl
# Public DNS record
resource "aws_route53_record" "client_public" {
  zone_id = var.route53_zone_id
  name    = "app.client-a.example.com"
  type    = "A"
  
  alias {
    name                   = module.client_alb.public_alb_dns_name
    zone_id                = module.client_alb.public_alb_zone_id
    evaluate_target_health = true
  }
}

# Internal DNS record
resource "aws_route53_record" "client_internal" {
  zone_id = var.route53_private_zone_id
  name    = "internal.client-a.example.com"
  type    = "A"
  
  alias {
    name                   = module.client_alb.internal_alb_dns_name
    zone_id                = module.client_alb.internal_alb_zone_id
    evaluate_target_health = true
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| client_id | Unique client identifier | string | - | yes |
| environment | Environment name | string | - | yes |
| vpc_id | VPC ID | string | - | yes |
| public_subnet_ids | Public subnet IDs for internet-facing ALB | list(string) | [] | conditional |
| private_subnet_ids | Private subnet IDs for internal ALB | list(string) | [] | conditional |
| eks_node_security_group_id | EKS node security group ID | string | - | yes |
| ssl_certificate_arn | SSL certificate ARN (ACM) | string | - | yes |
| alb_type | ALB type: internet-facing, internal, or both | string | "both" | no |
| https_external_port | External HTTPS port | number | 30443 | no |
| http_external_port | External HTTP port | number | 30080 | no |
| https_nodeport | NodePort for HTTPS | number | 30443 | no |
| http_nodeport | NodePort for HTTP | number | 30080 | no |
| redirect_http_to_https | Redirect HTTP to HTTPS | bool | true | no |
| ssl_policy | SSL security policy | string | ELBSecurityPolicy-TLS13-1-2-2021-06 | no |
| ssl_certificate_arn_internal | Separate SSL cert for internal ALB | string | null | no |
| health_check_path | Health check path | string | /healthz/ready | no |
| allowed_cidr_blocks_public | Allowed CIDRs for public ALB | list(string) | ["0.0.0.0/0"] | no |
| allowed_cidr_blocks_internal | Allowed CIDRs for internal ALB | list(string) | ["10.0.0.0/8"] | no |
| waf_acl_arn | WAF Web ACL ARN | string | null | no |
| enable_deletion_protection | Enable deletion protection | bool | true | no |
| enable_access_logs | Enable access logs | bool | true | no |
| access_logs_bucket | S3 bucket for access logs | string | "" | conditional |
| enable_sticky_sessions | Enable sticky sessions | bool | false | no |
| tags | Additional tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| public_alb_dns_name | DNS name of public ALB |
| public_alb_arn | ARN of public ALB |
| public_alb_zone_id | Route53 zone ID of public ALB |
| internal_alb_dns_name | DNS name of internal ALB |
| internal_alb_arn | ARN of internal ALB |
| internal_alb_zone_id | Route53 zone ID of internal ALB |
| target_group_arns | All target group ARNs |
| alb_endpoints | Map of ALB endpoints |
| alb_configuration_summary | Configuration summary |

## Security Considerations

1. **SSL/TLS** - Always use ACM certificates, never self-signed in production
2. **WAF** - Enable for public-facing ALBs to protect against common attacks
3. **Security Groups** - Module follows least-privilege (only ALB → EKS NodePort)
4. **Deletion Protection** - Enabled by default for production safety
5. **Access Logs** - Enable for audit and compliance requirements
6. **SSL Policy** - Defaults to TLS 1.3 + 1.2 for modern security
7. **CIDR Restrictions** - Configure `allowed_cidr_blocks_internal` for VPN access

## Multi-Client Deployment Pattern

```hcl
# clients.auto.tfvars
clients = {
  client-a = {
    tier = "premium"
    alb_config = {
      type                = "both"
      ssl_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/client-a"
      waf_enabled         = true
      vpn_cidrs           = ["10.200.0.0/16"]
    }
  }
  
  client-b = {
    tier = "standard"
    alb_config = {
      type                = "internal"
      ssl_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/client-b"
      waf_enabled         = false
      vpn_cidrs           = ["10.200.0.0/16"]
    }
  }
}

# main.tf - Layer 02
module "client_alb" {
  source = "../../../../../../../modules/alb-per-client"
  
  for_each = var.clients
  
  client_id                    = each.key
  environment                  = var.environment
  vpc_id                       = module.vpc[each.key].vpc_id
  public_subnet_ids            = module.vpc[each.key].public_subnet_ids
  private_subnet_ids           = module.vpc[each.key].private_subnet_ids
  eks_node_security_group_id   = module.eks[each.key].node_security_group_id
  alb_type                     = each.value.alb_config.type
  ssl_certificate_arn          = each.value.alb_config.ssl_certificate_arn
  waf_acl_arn                  = each.value.alb_config.waf_enabled ? module.waf[each.key].web_acl_arn : null
  allowed_cidr_blocks_internal = each.value.alb_config.vpn_cidrs
  access_logs_bucket           = "${each.key}-alb-logs-${var.region}"
  
  tags = module.tags[each.key].common_tags
}
```

## Testing

### Test ALB Health
```bash
# Public ALB
curl -k https://<public-alb-dns>:30443/healthz/ready

# Internal ALB (from VPN)
curl -k https://<internal-alb-dns>:30443/healthz/ready
```

### Test Traffic Flow
```bash
# Deploy test pod in EKS
kubectl run test-app --image=nginx --port=80

# Create Istio VirtualService
# Then test via ALB
curl -k https://<alb-dns>:30443/
```

## License

This module is part of the client-centric-infrastructure project.

## Authors

Platform Engineering Team

## Version

Version: 1.0.0  
Terraform: >= 1.0  
AWS Provider: ~> 5.0
