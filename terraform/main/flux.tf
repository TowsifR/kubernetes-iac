provider "flux" {
  kubernetes = {
    host                   = module.kind-cluster.cluster_endpoint
    client_certificate     = module.kind-cluster.client_certificate
    client_key             = module.kind-cluster.client_key
    cluster_ca_certificate = module.kind-cluster.cluster_ca_certificate
  }
  git = {
    url    = "https://github.com/${var.github_owner}/${var.github_repository}.git"
    branch = "master"
    http = {
      username = "git"
      password = var.github_token
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [module.kind-cluster]

  embedded_manifests = true
  path               = "kubernetes/clusters/${var.env}/${var.cluster_type}"
}