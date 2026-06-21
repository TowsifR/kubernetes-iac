# Calico CNI — installs before Flux bootstrap so Flux pods have networking:
#   kind_cluster -> helm_release.calico -> flux_bootstrap_git

provider "helm" {
  kubernetes = {
    host                   = module.kind-cluster.cluster_endpoint
    client_certificate     = module.kind-cluster.client_certificate
    client_key             = module.kind-cluster.client_key
    cluster_ca_certificate = module.kind-cluster.cluster_ca_certificate
  }
}

resource "helm_release" "calico" {
  name             = "calico"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  version          = "v3.30.7" # supports k8s 1.32
  namespace        = "tigera-operator"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    installation = {
      cni = { type = "Calico" }
      calicoNetwork = {
        ipPools = [{
          cidr          = "192.168.0.0/16" # must match the kind-cluster pod_subnet
          encapsulation = "VXLANCrossSubnet"
        }]
      }
      controlPlaneReplicas = 1
    }
    apiServer = { enabled = true } # manage/inspect Calico via kubectl
  })]

  depends_on = [module.kind-cluster]
}
