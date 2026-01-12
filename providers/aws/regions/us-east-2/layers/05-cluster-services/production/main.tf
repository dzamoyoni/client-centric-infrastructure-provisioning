# Cluster Services Layer - Production
# ESSENTIAL KUBERNETES SERVICES - PER-CLIENT DEPLOYMENT
# Deploys essential cluster services to each client's dedicated EKS cluster.
# These are NOT shared between clients - each client cluster gets its own stack.
# Services: Cluster Autoscaler, AWS Load Balancer Controller, Metrics Server, ExternalDNS, Istio

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  backend "s3" {
    # Backend configuration loaded from file
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project         = "${var.region}-${var.environment}"
      Environment     = var.environment
      ManagedBy       = "Terraform"
      CriticalInfra   = "true"
      BackupRequired  = "true"
      SecurityLevel   = "High"
      Region          = var.region
      Layer           = "ClusterServices"
      DeploymentPhase = "Phase-2"
    }
  }
}

# DATA SOURCES - Foundation and Platform Layer Outputs
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/01-foundation/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = "providers/aws/regions/${var.region}/layers/02-platform/${var.environment}/terraform.tfstate"
    region = var.terraform_state_region
  }
}

# DATA SOURCES - EKS and AWS Account Info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# LOCALS - Per-Client Configuration
locals {
  # Foundation layer outputs - per-client VPCs
  client_vpcs = data.terraform_remote_state.foundation.outputs.client_vpcs
  
  # Platform layer outputs - per-client EKS clusters
  client_clusters = data.terraform_remote_state.platform.outputs.client_clusters
  
  # Filter enabled clients
  enabled_clients = {
    for name, config in var.clients : name => config
    if config.enabled
  }
  
  # Validate all enabled clients have clusters
  missing_clusters = [
    for name in keys(local.enabled_clients) : name
    if !contains(keys(local.client_clusters), name)
  ]
  
  # Standard tags for all services
  standard_tags = {
    Project         = "${var.region}-${var.environment}"
    Environment     = var.environment
    ManagedBy       = "Terraform"
    CriticalInfra   = "true"
    BackupRequired  = "true"
    SecurityLevel   = "High"
    Region          = var.region
    Layer           = "SharedServices"
    DeploymentPhase = "Phase-2"
    Architecture    = "Per-Client-Isolated"
  }
}

# NOTE: Kubernetes and Helm providers configured per-client using aliases in module blocks below

# =============================================================================
# PER-CLIENT CLUSTER SERVICES - Each client gets dedicated services in their cluster
# =============================================================================
# These are essential Kubernetes services that every cluster needs.
# They are NOT shared between clients - completely isolated per client.

module "client_cluster_services" {
  source   = "../../../../../../../modules/shared-services"
  for_each = local.enabled_clients

  # Core project configuration
  # project_name removed - using client-centric naming
  environment  = var.environment
  region       = var.region

  # Client-specific EKS cluster information
  cluster_name            = local.client_clusters[each.key].cluster_name
  cluster_endpoint        = local.client_clusters[each.key].cluster_endpoint
  cluster_ca_certificate  = base64decode(local.client_clusters[each.key].cluster_certificate_authority_data)
  oidc_provider_arn       = local.client_clusters[each.key].oidc_provider_arn
  cluster_oidc_issuer_url = local.client_clusters[each.key].cluster_oidc_issuer_url
  vpc_id                  = local.client_vpcs[each.key].vpc_id

  # Service configuration
  enable_cluster_autoscaler           = var.enable_cluster_autoscaler
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller
  enable_metrics_server               = var.enable_metrics_server
  enable_external_dns                 = var.enable_external_dns

  # Cluster autoscaler configuration
  cluster_autoscaler_version = var.cluster_autoscaler_version

  # AWS Load Balancer Controller configuration
  aws_load_balancer_controller_version = var.aws_load_balancer_controller_version

  # DNS configuration - use dynamically created zone for this client
  dns_zone_ids                = var.enable_external_dns ? [try(aws_route53_zone.client_zones[each.key].zone_id, "")] : []
  external_dns_version        = var.external_dns_version
  external_dns_domain_filters = var.enable_external_dns ? ["${each.key}.${var.parent_dns_zone}"] : []
  external_dns_policy         = var.external_dns_policy

  # Client-specific tags
  additional_tags = merge(
    local.standard_tags,
    {
      Client       = each.key
      ClientTier   = each.value.tier
      ClientCode   = each.value.client_code
      CostCenter   = each.value.metadata.cost_center
      BusinessUnit = each.value.metadata.business_unit
    }
  )
}

# =============================================================================
# PER-CLIENT ISTIO SERVICE MESH - PRODUCTION GRADE
# =============================================================================
# Deploy Istio to each client's cluster if enabled for that client

module "client_istio_service_mesh" {
  source   = "../../../../../../../modules/istio-service-mesh"
  for_each = var.enable_istio_service_mesh ? local.enabled_clients : {}

  # Core project configuration
  # project_name removed - using client-centric naming
  environment  = var.environment
  region       = var.region
  cluster_name = local.client_clusters[each.key].cluster_name

  # Istio configuration
  istio_version   = var.istio_version
  mesh_id         = "${var.istio_mesh_id}-${each.key}"
  cluster_network = var.istio_cluster_network
  trust_domain    = var.istio_trust_domain

  # Ambient mode configuration
  enable_ambient_mode = var.enable_istio_ambient_mode

  # Ingress gateway configuration - ClusterIP for internal routing
  enable_ingress_gateway            = var.enable_istio_ingress_gateway
  ingress_gateway_replicas          = var.istio_ingress_gateway_replicas
  ingress_gateway_resources         = var.istio_ingress_gateway_resources
  ingress_gateway_autoscale_enabled = var.istio_ingress_gateway_autoscale_enabled
  ingress_gateway_autoscale_min     = var.istio_ingress_gateway_autoscale_min
  ingress_gateway_autoscale_max     = var.istio_ingress_gateway_autoscale_max

  # Production resource configuration
  istiod_resources         = var.istio_istiod_resources
  istiod_autoscale_enabled = var.istio_istiod_autoscale_enabled
  istiod_autoscale_min     = var.istio_istiod_autoscale_min
  istiod_autoscale_max     = var.istio_istiod_autoscale_max

  # Application namespace configuration
  application_namespaces = var.istio_application_namespaces

  # Observability integration
  enable_distributed_tracing = var.enable_istio_distributed_tracing
  enable_access_logging      = var.enable_istio_access_logging
  tracing_sampling_rate      = var.istio_tracing_sampling_rate

  # Monitoring integration
  enable_service_monitor  = var.enable_istio_service_monitor
  enable_prometheus_rules = var.enable_istio_prometheus_rules

  # System node tolerations for ztunnel and CNI DaemonSets
  ztunnel_tolerations = [
    {
      key      = "node.kubernetes.io/not-ready"
      operator = "Exists"
      value    = ""
      effect   = "NoExecute"
    },
    {
      key      = "node.kubernetes.io/unreachable"
      operator = "Exists"
      value    = ""
      effect   = "NoExecute"
    },
    {
      key      = "workload-type"
      operator = "Equal"
      value    = "system"
      effect   = "NoSchedule"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "cluster-services"
      effect   = "NoSchedule"
    }
  ]

  cni_tolerations = [
    {
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      value    = ""
      effect   = ""
    },
    {
      key      = "workload-type"
      operator = "Equal"
      value    = "system"
      effect   = "NoSchedule"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "cluster-services"
      effect   = "NoSchedule"
    }
  ]

  # Client-specific tags
  additional_tags = merge(
    local.standard_tags,
    {
      Client       = each.key
      ClientTier   = each.value.tier
      ClientCode   = each.value.client_code
      CostCenter   = each.value.metadata.cost_center
      BusinessUnit = each.value.metadata.business_unit
    }
  )

  # Ensure cluster services are deployed first
  depends_on = [module.client_cluster_services]
}


