output "cluster_name" {                                                                                                                                                       
    value = module.kind-cluster.cluster_name                                                                                                                                    
  }                                                                                                                                                                             
                                                                                                                                                                                
output "cluster_endpoint" {                                                                                                                                                   
  value = module.kind-cluster.cluster_endpoint                                                                                                                                
}                                                                                                                                                                             
                                                                                                                                                                              
output "kustomize_path" {                                                                                                                                                     
  description = "Path to apply Kubernetes manifests"                                                                                                                          
  value       = "../../kubernetes/clusters/${var.env}/${var.cluster_type}"                                                                                                    
}