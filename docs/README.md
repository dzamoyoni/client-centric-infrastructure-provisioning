## Why This Project Exists

This repository provides a **production-ready, client-isolated Terraform architecture** for AWS.

It is designed for:
- SaaS providers onboarding multiple enterprise clients
- Strong network isolation and security boundaries
- Centralized egress and cost optimization
- Per-client Kubernetes, databases, and observability

If you need **true tenant isolation** without duplicating shared infrastructure, this repo is for you.


## Key Features

- **Hard client isolation** (VPC, EKS, DB per client)
- **Centralized egress** via Transit Gateway + Egress VPC
- **Per-client Kubernetes clusters**
- **Dedicated observability stacks** (Prometheus, Grafana, Loki, Tempo)
- **CIDR registry & validation** to prevent network collisions
- **Cost-aware tagging strategy**

## Architecture at a Glance

- **Hub-and-spoke networking** using AWS Transit Gateway
- **Single Egress VPC** handles all outbound internet traffic
- **Client VPCs are NAT-less** for cost and security
- **Optional per-client VPN** integrates cleanly with TGW routing

 Full design rationale: [Transit Gateway Architecture](docs/TRANSIT-GATEWAY-ARCHITECTURE.md)


**Client-Centric Infrastructure - Enterprise Documentation**

---

## Available Documentation

### Core Infrastructure Guides

#### [Infrastructure as a Product](./INFRASTRUCTURE-AS-A-PRODUCT.md) 📖 **Executive & Team Overview**
**Status**: Production  
**Audience**: All teams, leadership, stakeholders

Comprehensive document explaining the architecture philosophy, design rationale, benefits, standards alignment, and why this infrastructure represents a reliable, top-notch system. Includes GitOps readiness assessment.

#### [Getting Started](./GETTING-STARTED.md) 🚀 **Start Here**
**Status**: Production  
**Audience**: Anyone deploying infrastructure

Complete step-by-step guide for onboarding your first client including prerequisites, layer deployment, and verification.

#### [Architecture Deep Dive](./ARCHITECTURE.md) 🏗️ **Design Reference**
**Status**: Production  
**Audience**: Engineers, architects, DevOps

Detailed explanation of hub-and-spoke model, CIDR strategy, traffic flows, and cost optimization rationale.

#### [Layer Deployment Guide](./LAYER-DEPLOYMENT.md) 📦 **Deployment Reference**
**Status**: Production  
**Audience**: Platform engineers, DevOps

Complete reference for deploying all 7 infrastructure layers (00-06) with configuration examples.

#### [Networking Guide](./NETWORKING.md) 🌐 **Network Design**
**Status**: Production  
**Audience**: Network engineers, platform team

Transit Gateway architecture, VPN integration, routing details, and troubleshooting.

#### [Client Configuration](./CLIENT-CONFIGURATION.md) ⚙️ **Configuration Guide**
**Status**: Production  
**Audience**: Platform engineers

Complete guide to clients.auto.tfvars, terraform.tfvars, and CIDR registry management.

#### [Helper Scripts](./HELPER-SCRIPTS.md) 🛠️ **Automation Reference**
**Status**: Production  
**Audience**: DevOps, SRE

Documentation for all automation scripts (CIDR validation, S3 provisioning, security audits).

#### [Troubleshooting](./TROUBLESHOOTING.md) 🔧 **Problem Solving**
**Status**: Production  
**Audience**: All engineers

Common issues and solutions: CIDR conflicts, EKS access, state locks, DNS, scaling.

#### [Maintenance Operations](./MAINTENANCE.md) 🔄 **Operations Guide**
**Status**: Production  
**Audience**: SRE, platform team

Kubernetes upgrades, scaling operations, backup/disaster recovery procedures.

#### [Security Best Practices](./SECURITY.md) 🔒 **Security Hardening**
**Status**: Production  
**Audience**: Security team, DevOps

Secret management, MFA, state bucket access, IAM policies, security audits.

#### [Cost Optimization](./COST-OPTIMIZATION.md) 💰 **FinOps Guide**
**Status**: Production  
**Audience**: FinOps, platform team

Per-client cost tracking, optimization strategies, spot instances, lifecycle policies.

---

---

## Additional Resources

**Tagging & Compliance**: If you have enterprise tagging documentation (tagging-standards.md, aws-config-tag-compliance.md), they would be linked here.

**Cost Tracking**: See [Cost Optimization Guide](./COST-OPTIMIZATION.md) for per-client cost tracking strategies.

---

## Quick Start

### For New Engineers
1. **Read**: [Getting Started](./GETTING-STARTED.md)
2. **Understand**: Architecture and design decisions
3. **Deploy**: Follow layer deployment guide
4. **Verify**: Use troubleshooting guide if needed

### For Client Onboarding
1. **Read**: [Getting Started](./GETTING-STARTED.md) (REQUIRED)
2. **Configure**: Edit `clients.auto.tfvars` with client definition
3. **Validate**: Run `./scripts/validate-cidr.sh`
4. **Deploy**: Follow layer deployment sequence (00-06)
5. **Verify**: Check network connectivity and DNS

### For Platform Engineers
1. **Read**: Both documents
2. **Implement**: Deploy AWS Config rules
3. **Monitor**: Set up compliance dashboards
4. **Enforce**: Configure automated alerts
5. **Review**: Monthly compliance reports

### For DevOps/SRE
1. **Read**: [Enterprise Tagging Standards](./tagging-standards.md)
2. **Integrate**: Add tag validation to CI/CD pipelines
3. **Automate**: Use pre-commit hooks
4. **Monitor**: Track tag compliance metrics

---

## Quick Start for Common Scenarios

### Adding a New Client

**⚠️ Required:** Read [Adding New Clients Guide](./adding-new-clients.md) first!

```bash
# 1. Add client definition to clients.auto.tfvars (following the guide)
# 2. Client will automatically inherit all 60+ enterprise tags
# 3. Validate configuration
cd providers/aws/regions/us-east-2/layers/01-foundation/production
terraform validate
terraform plan

# 4. Check tag compliance
terraform output -json tag_compliance
```

### Checking Tag Compliance

```bash
cd providers/aws/regions/us-east-2/layers/<layer>/production

# Check tag compliance
terraform output -json tag_compliance

# Expected output:
# {
#   "status": "OK",
#   "tag_count": 42,
#   "tag_limit": 45
# }
```

---

## Related Documentation

| Document | Location | Description |
|----------|----------|-------------|
| **Main README** | [../README.md](../README.md) | Architecture overview, quick start |
| **Tagging Module** | [../modules/tagging/](../modules/tagging/) | Terraform tagging module |
| **Tagging Module README** | [../modules/tagging/README.md](../modules/tagging/README.md) | Module usage guide |
| **CIDR Registry** | [../cidr-registry.yaml](../cidr-registry.yaml) | VPC CIDR allocation |
| **Scripts** | [../scripts/](../scripts/) | Helper automation scripts |
| **Clients Config** | [../clients.auto.tfvars](../clients.auto.tfvars) | Client definitions |

---

## Compliance Checklist

Use this checklist before deploying any infrastructure:

### Pre-Deployment
- [ ] All required tags configured in tagging module
- [ ] `tag_compliance` output shows `status = "OK"`
- [ ] Tag count < 45 (safe limit)
- [ ] Client tag present (for client-centric resources)
- [ ] Cost allocation tags configured

### Post-Deployment
- [ ] AWS Config rules validate compliance
- [ ] Cost Explorer shows resources with correct tags
- [ ] No non-compliant resources in AWS Config dashboard
- [ ] Monitoring alerts configured based on tags

### Monthly Review
- [ ] Review non-compliant resources
- [ ] Update tagging standards if needed
- [ ] Verify cost allocation accuracy
- [ ] Audit TBAC policies

---

## Getting Help

### Questions About Tagging?
- **Slack**: #platform-engineering
- **Email**: platform-team@company.com
- **On-call**: Platform Engineering rotation

### Report Issues
- **Non-compliant resources**: File ticket with Platform team
- **Tagging standard updates**: Submit RFC
- **Module bugs**: Create GitHub issue

### Training
- **Onboarding**: Tagging standards covered in week 1
- **Workshops**: Monthly "Terraform Best Practices" session
- **Documentation**: Always refer to latest version in `docs/`

---

## Document Updates

| Date | Document | Changes | Author |
|------|----------|---------|--------|
| 2026-01-26 | Adding New Clients Guide | Initial release | Platform Engineering |
| 2026-01-26 | Tagging Standards v2.0 | Industrial standards upgrade | Platform Engineering |
| 2026-01-26 | AWS Config Compliance | Initial release | Platform Engineering |
| 2026-01-26 | Tagging Module README | Initial release | Platform Engineering |

---

## Contributing

### Adding New Documentation
1. Create Markdown file in `docs/`
2. Add entry to this README
3. Update table of contents
4. Submit pull request

### Updating Existing Docs
1. Update document
2. Update "Last Updated" date
3. Add entry to revision history
4. Submit pull request

---

## Standards Compliance

All documentation in this directory follows:
- **Markdown Best Practices**: CommonMark spec
- **Code Examples**: Tested in dev environment
- **Version Control**: All changes tracked in Git
- **Review Process**: Platform team approval required
- **Accessibility**: Clear headings, code blocks, tables

---

**Maintained By**: Platform Engineering Team  
**Contact**: platform-team@company.com  
