resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = false # nodes stay NotReady until Calico (the CNI) is installed

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Disable kindnet so Calico can be the CNI (kindnet doesn't enforce NetworkPolicy).
    networking {
      disable_default_cni = true
      pod_subnet          = "192.168.0.0/16" # must match Calico's ipPool
    }

    node {
      role  = "control-plane"
      image = "kindest/node:${var.kubernetes_version}"

      extra_port_mappings {
        container_port = 30080
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 30443
        host_port      = 443
      }
    }

    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role  = "worker"
        image = "kindest/node:${var.kubernetes_version}"
      }
    }
  }
}
