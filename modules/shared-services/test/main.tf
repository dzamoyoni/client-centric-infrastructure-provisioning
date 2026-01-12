# Test configuration for improved shared-services modules
# This validates our module improvements work correctly

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Test our improved ALB Controller module
module "test_aws_load_balancer_controller" {
  source = "../aws-load-balancer-controller"

  # Core configuration
  cluster_name = "test-cluster"
  region       = "us-east-1"
  environment  = "test"
  vpc_id       = "vpc-12345678"

  # IAM configuration  
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890ABCDEF"

  # Service configuration
  helm_chart_version   = "1.8.1"
  service_account_name = "test-aws-load-balancer-controller-sa"

  # Test external IRSA role (optional)
  external_irsa_role_arn = null # Using internal role creation

  tags = {
    Test = "SharedServicesModuleFixes"
  }
}

# Test our improved Cluster Autoscaler module  
module "test_cluster_autoscaler" {
  source = "../cluster-autoscaler"

  # Core configuration
  cluster_name = "test-cluster"
  region       = "us-east-1"
  environment  = "test"

  # IAM configuration
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890ABCDEF"

  # Service configuration
  helm_chart_version   = "9.37.0"
  service_account_name = "test-cluster-autoscaler-sa"

  # Test external IRSA role (optional)
  external_irsa_role_arn = null # Using internal role creation

  tags = {
    Test = "SharedServicesModuleFixes"
  }
}
