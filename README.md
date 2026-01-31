# Client-Centric Terraform Infrastructure

> **Production-ready, multi-tenant AWS infrastructure with true client isolation**

[Terraform]https://www.terraform.io/
[AWS]https://aws.amazon.com/

---

## What This Does

This repository provides **production-grade infrastructure** for SaaS providers needing hard client isolation. Each client gets their own VPC, Kubernetes cluster, databases, and monitoring stack — while sharing a centralized egress path for cost optimization.

**Perfect for**: Multi-tenant SaaS, enterprise client onboarding, compliance-heavy industries (healthcare, finance, government)

---

## ✨ Key Features

- 🏢 **True Client Isolation** — Dedicated VPC, EKS, DB, and observability per client
- 🌐 **Centralized Egress** — Single Egress VPC via Transit Gateway (67% NAT cost reduction)
- 🚀 **Rapid Onboarding** — Add new clients in ~2 hours with automated deployment
- 📊 **Built-in Observability** — Prometheus, Grafana, Loki, Tempo per client
- 🔒 **Security by Default** — VPC isolation, KMS encryption, VPC Flow Logs, optional VPN
- 💰 **Cost-Aware Tagging** — Automatic per-client cost tracking and FinOps integration
- 📏 **CIDR Registry** — Validated CIDR allocation prevents network conflicts
- 🔄 **Auto-Scaling** — Cluster Autoscaler, HPA, and right-sized resources

---

## Architecture at a Glance

```
                          Internet
                             │
                    ┌────────┴────────┐
                    │   Egress VPC    │  ← Single NAT Gateway pair
                    │  10.255.0.0/16  │     (cost-shared)
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │ Transit Gateway │  ← Routing hub
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────┴─────┐    ┌────┴────┐    ┌─────┴─────┐
      │ Client A  │    │Client B │    │ Client C  │
      │ • VPC     │    │ • VPC   │    │ • VPC     │
      │ • EKS     │    │ • EKS   │    │ • EKS     │
      │ • DB      │    │ • DB    │    │ • DB      │
      │ • Logs    │    │ • Logs  │    │ • Logs    │
      └───────────┘    └─────────┘    └───────────┘
```

**Traffic Flow**: Client Pod → Transit Gateway → Egress VPC → NAT Gateway → Internet

**Deep Dive**: [Full Architecture Documentation](docs/ARCHITECTURE.md)

---

## Quick Start

### Prerequisites

```bash
# Required tools
terraform version  # >= 1.5.0
aws --version      # >= 2.x
kubectl version    # latest

# Configure AWS
aws configure
```

### Deploy Your First Client

```bash
# 1. Define client
nano providers/aws/regions/us-east-2/layers/01-foundation/production/clients.auto.tfvars

# 2. Validate CIDR
./scripts/validate-cidr.sh

# 3. Deploy layers (in order)
cd providers/aws/regions/us-east-2/layers/00-bootstrap/production
terraform init && terraform apply

cd ../01-foundation/production
terraform init -backend-config=backend.hcl && terraform apply

cd ../01.5-transit-gateway/production
terraform init -backend-config=backend.hcl && terraform apply

cd ../02-platform/production
terraform init -backend-config=backend.hcl && terraform apply

# ... continue through layers 03-06
```

📘 **Full Guide**: [Getting Started Documentation](docs/GETTING-STARTED.md)

---

## Infrastructure Layers

| Layer | Purpose | Deploy Time | Dependencies |
|-------|---------|-------------|--------------|
| **00 - Bootstrap** | S3 backend + KMS + observability buckets | 5 min | None (one-time) |
| **01 - Foundation** | Egress VPC + client VPCs (NAT-less) | 10 min | Layer 00 |
| **01.5 - Transit Gateway** | Centralized routing hub | 15 min | Layer 01 |
| **02 - Platform** | EKS clusters per client | 20 min | Layer 01.5 |
| **03 - Database** | PostgreSQL master + replica | 15 min | Layer 01 |
| **04 - Compute** | Analytics/batch instances (optional) | 5 min | Layer 01 |
| **05 - Cluster Services** | Autoscaler, ALB, DNS, Istio | 15 min | Layer 02 |
| **06 - Observability** | Prometheus, Grafana, Loki, Tempo | 15 min | Layer 02 |

**Total Time**: ~2 hours for complete client setup

<details>
<summary>📋 View complete onboarding checklist</summary>

```
□ Allocate unique VPC CIDR (10.X.0.0/16)
□ Update clients.auto.tfvars in all layers
□ Update cidr-registry.yaml
□ Run ./scripts/validate-cidr.sh
□ Deploy Layer 00 (if first time)
□ Deploy Layer 01 (Foundation)
□ Deploy Layer 01.5 (Transit Gateway)
□ Deploy Layer 02 (Platform/EKS)
□ Create database-secrets.tfvars
□ Deploy Layer 03 (Database)
□ Deploy Layer 04 (Compute, if needed)
□ Deploy Layer 05 (Cluster Services)
□ Deploy Layer 06 (Observability)
□ Configure kubectl context
□ Verify network connectivity
□ Test DNS resolution
□ Access Grafana dashboard
```

</details>

📘 **Deep Dive**: [Complete Layer Deployment Guide](docs/LAYER-DEPLOYMENT.md)

---

## Repository Structure

```
client-centric-infrastructure/
├── providers/aws/regions/us-east-2/layers/
│   ├── 00-bootstrap/            # S3 state + KMS + observability buckets
│   ├── 01-foundation/           # Egress VPC + client VPCs
│   ├── 01.5-transit-gateway/    # Centralized routing
│   ├── 02-platform/             # EKS clusters
│   ├── 03-database/             # PostgreSQL
│   ├── 04-standalone-compute/   # Analytics instances
│   ├── 05-cluster-services/     # K8s controllers
│   └── 06-observability/        # Monitoring stack
├── modules/                      # Reusable Terraform modules
├── scripts/                      # Automation scripts
├── docs/                         # Complete documentation
└── cidr-registry.yaml            # CIDR allocation tracking
```

---

## Common Commands

```bash
# Validate CIDR allocations
./scripts/validate-cidr.sh

# Access client EKS cluster
aws eks update-kubeconfig --region us-east-2 --name client-name-prod-us-east-2 --alias client-name
kubectl --context client-name get nodes

# View Grafana dashboard
kubectl --context client-name port-forward -n observability svc/grafana 3000:80

# Check per-client costs
aws ce get-cost-and-usage --group-by Type=TAG,Key=Client
```

---

## Documentation Hub

### 📚 Core Documentation

- **[Getting Started](docs/GETTING-STARTED.md)** — Step-by-step onboarding guide
- **[Architecture](docs/ARCHITECTURE.md)** — Design philosophy and network model
- **[Layer Deployment](docs/LAYER-DEPLOYMENT.md)** — Complete Layer 00-06 reference
- **[Networking](docs/NETWORKING.md)** — Transit Gateway, VPN, routing deep dive

### 🔧 Operations

- **[Troubleshooting](docs/TROUBLESHOOTING.md)** — Common issues and solutions
- **[Maintenance](docs/MAINTENANCE.md)** — Upgrades, scaling, backup/DR
- **[Helper Scripts](docs/HELPER-SCRIPTS.md)** — Automation script reference

### 🔐Security & Compliance

- **[Security](docs/SECURITY.md)** — Best practices and hardening
- **[Client Configuration](docs/CLIENT-CONFIGURATION.md)** — tfvars guide
- **[Enterprise Tagging](docs/README.md)** — Tagging standards and compliance

### 💰 Cost Management

- **[Cost Optimization](docs/COST-OPTIMIZATION.md)** — FinOps guide
- **NAT Gateway Savings**: 67% reduction vs per-client NAT
- **Spot Instances**: Optional for non-prod workloads
- **S3 Lifecycle**: Auto-archive old data

---

## Cost Breakdown (Example: 3 Clients)

| Component | Monthly Cost | Notes |
|-----------|--------------|-------|
| Egress VPC NAT (2 AZs) | $65.70 | Shared across all clients |
| Transit Gateway | $146 | $36.50 per VPC attachment |
| EKS clusters (3) | $219 | $73/cluster + node costs |
| EKS nodes (t3.medium × 6) | ~$150 | Variable based on utilization |
| Databases (PostgreSQL × 3) | ~$200 | t3.large instances |
| S3 + Observability | ~$50 | With lifecycle policies |
| **Total** | **~$830/month** | **~$277 per client** |

**Savings vs Traditional**: **$131/month** on NAT alone (67% reduction)

📘 **Deep Dive**: [Cost Optimization Guide](docs/COST-OPTIMIZATION.md)

---

## Key Design Decisions

### Why NAT-less Client VPCs?

**Problem**: Per-client NAT Gateways cost $65.70/month each  
**Solution**: Single Egress VPC + Transit Gateway routing  
**Result**: 67% cost reduction, centralized security

### Why Transit Gateway?

- **Scalability**: Connect 5,000 VPCs vs manual peering
- **Routing**: Centralized policy management
- **VPN**: Coexists with on-premises connectivity

### Why Separate EKS per Client?

- **Isolation**: Noisy neighbor prevention
- **Compliance**: Hard boundaries for SOC2/HIPAA
- **Blast Radius**: Failures contained to single client

📘 **Deep Dive**: [Architecture Documentation](docs/ARCHITECTURE.md)

---

## Network Features

### Transit Gateway Routing

- **Internet Traffic**: Client → TGW → Egress VPC → NAT → Internet
- **VPN Traffic**: Client → VPN Gateway → On-premises (longest-prefix match)
- **Cross-Client**: Disabled by default (security)

### VPN Integration (Optional)

Per-client Site-to-Site VPN:
- Dual tunnels (high availability)
- BGP or static routing
- Coexists with TGW egress

📘 **Deep Dive**: [Networking Guide](docs/NETWORKING.md)

---

## Observability Stack (Per Client)

Each client gets isolated monitoring:

- **Prometheus** — Metrics collection (7-15 day retention)
- **Grafana** — Visualization dashboards
- **Loki** — Log aggregation
- **Tempo** — Distributed tracing
- **Fluent Bit** — Log forwarding
- **AlertManager** — Alert routing (email/Slack)

**Storage**: S3 with Intelligent-Tiering for long-term retention

---

## Security Highlights

✅ **Network Isolation**: VPC-level separation  
✅ **Encryption at Rest**: KMS for all data stores  
✅ **Encryption in Transit**: TLS everywhere  
✅ **State File Security**: KMS-encrypted S3 backend  
✅ **VPC Flow Logs**: Network traffic monitoring  
✅ **Secrets Management**: AWS Secrets Manager  
✅ **RBAC**: Kubernetes role-based access  
✅ **Tag-Based Access**: Per-client IAM policies

📘 **Deep Dive**: [Security Guide](docs/SECURITY.md)

---

## Troubleshooting Quick Reference

| Issue | Quick Fix | Documentation |
|-------|-----------|---------------|
| CIDR conflict | Run `./scripts/validate-cidr.sh` | [Getting Started](docs/GETTING-STARTED.md) |
| EKS unreachable | Update kubeconfig, check SGs | [Troubleshooting](docs/TROUBLESHOOTING.md#eks-unreachable) |
| State lock error | `terraform force-unlock <id>` | [Troubleshooting](docs/TROUBLESHOOTING.md#state-locks) |
| Pods not scaling | Check autoscaler logs | [Troubleshooting](docs/TROUBLESHOOTING.md#autoscaling) |
| DNS not resolving | Verify ExternalDNS, Route53 | [Troubleshooting](docs/TROUBLESHOOTING.md#dns) |

📘 **Full Guide**: [Troubleshooting Documentation](docs/TROUBLESHOOTING.md)

---

## Support & Contributing

### Getting Help

- **Documentation**: Browse [docs/](docs/) directory
- **Slack**: #platform-engineering
- **Email**: platform-team@company.com
- **On-Call**: PagerDuty rotation

### Contributing

1. Create feature branch: `git checkout -b feature/client-onboarding`
2. Make changes and test
3. Run validation: `./scripts/validate-cidr.sh`
4. Submit PR with description
5. Tag platform team for review

---

## License

Proprietary — Internal use only

---

## Changelog

### v2.0.0 (January 2026)
- ✨ Added Layer 00 (Bootstrap) for Terraform-managed S3 backend
- ✨ Introduced Transit Gateway for centralized routing
- ✨ Migrated to NAT-less client VPCs (67% cost reduction)
- ✨ Implemented KMS encryption for state files
- ✨ Added per-client observability S3 buckets
- ✨ VPN + Transit Gateway integration support
- 🐛 Fixed CIDR subnet allocation conflicts

---

**Maintained By**: Platform Engineering Team  
**Last Updated**: January 31, 2026  
**Version**: 2.0.0
