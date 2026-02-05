module "kind-cluster" {                                                                                                                                                       
    source = "../modules/kind-cluster"                                                                                                                                          
                                                                                                                                                                                
    cluster_name       = var.cluster_name                                                                                                                                       
    cluster_type       = var.cluster_type                                                                                                                                       
    kubernetes_version = var.kubernetes_version                                                                                                                                 
    worker_node_count  = var.worker_node_count                                                                                                                                  
    env                = var.env                                                                                                                                                
    common_labels      = local.all_labels                                                                                                                                       
  }