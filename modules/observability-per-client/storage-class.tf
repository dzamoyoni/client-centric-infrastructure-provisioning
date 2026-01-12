# =============================================================================
# Storage Class - GP2 CSI
# =============================================================================
# Note: In a per-client architecture, storage classes are typically created
# once per cluster (not per client). This resource uses create_before_destroy
# and will skip if already exists.
# =============================================================================

resource "kubernetes_storage_class_v1" "gp2_csi" {
  metadata {
    name = "gp2-csi"
  }

  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Retain"
  
  parameters = {
    type      = "gp2"
    encrypted = "true"
    fsType    = "ext4"
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [metadata[0].annotations]
  }
}
