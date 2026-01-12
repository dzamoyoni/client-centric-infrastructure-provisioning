data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}
