locals {
  all_labels = merge(var.common_labels, {
    "environment"  = var.env
    "cluster-type" = var.cluster_type
  })
}