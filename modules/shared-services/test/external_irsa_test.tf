# Test configuration for external IRSA role functionality

# Test ALB Controller with external IRSA role
module "test_aws_load_balancer_controller_external_irsa" {
  source = "../aws-load-balancer-controller"

  # Core configuration
  cluster_name = "test-cluster-external"
  region       = "us-east-1"
  environment  = "test"
  vpc_id       = "vpc-12345678"

  # IAM configuration  
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890ABCDEF"

  # Service configuration
  helm_chart_version   = "1.8.1"
  service_account_name = "test-alb-controller-external-sa"

  # Test external IRSA role (using external role)
  external_irsa_role_arn = "arn:aws:iam::123456789012:role/ExternalALBControllerRole"

  tags = {
    Test = "ExternalIRSA-ALBController"
  }
}

# Test Cluster Autoscaler with external IRSA role
module "test_cluster_autoscaler_external_irsa" {
  source = "../cluster-autoscaler"

  # Core configuration
  cluster_name = "test-cluster-external"
  region       = "us-east-1"
  environment  = "test"

  # IAM configuration
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890ABCDEF"

  # Service configuration
  helm_chart_version   = "9.37.0"
  service_account_name = "test-cluster-autoscaler-external-sa"

  # Test external IRSA role (using external role)
  external_irsa_role_arn = "arn:aws:iam::123456789012:role/ExternalClusterAutoscalerRole"

  tags = {
    Test = "ExternalIRSA-ClusterAutoscaler"
  }
}
