variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = null # Uses latest compatible version
}

variable "node_group_role_names" {
  description = "List of existing node group IAM role names to attach EBS CSI policy (fallback for legacy clusters)"
  type        = list(string)
  default     = []
}

variable "create_gp2_storageclass" {
  description = "Whether to create GP2 StorageClass"
  type        = bool
  default     = true
}

variable "create_gp3_storageclass" {
  description = "Whether to create GP3 StorageClass"
  type        = bool
  default     = false
}

variable "make_gp2_default" {
  description = "Whether to make GP2 the default StorageClass"
  type        = bool
  default     = true
}

variable "make_gp3_default" {
  description = "Whether to make GP3 the default StorageClass"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
