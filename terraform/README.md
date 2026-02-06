# Terraform - KinD Cluster + Flux Bootstrap

This Terraform configuration creates local Kubernetes clusters using [KinD (Kubernetes in Docker)](https://kind.sigs.k8s.io/) and bootstraps [Flux CD](https://fluxcd.io/) for GitOps.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running, WSL2 integration enabled)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- GitHub Personal Access Token with `repo` scope

## Quick Start (Makefile)

```bash
# 1. Create .env file in project root with your GitHub token
echo 'export TF_VAR_github_token=ghp_your_token' > ../.env

# 2. Create terraform.tfvars with your identity
cp main/terraform.tfvars.example main/terraform.tfvars
# Edit main/terraform.tfvars with your GitHub username and repo

# 3. Run
make init      # Initialize Terraform
make cluster   # Create cluster + bootstrap Flux

# Other commands
make destroy   # Tear down cluster
make clean     # Remove all clusters + Terraform cache
```

## Directory Structure

```
terraform/
├── Makefile                    # Simplified commands
├── main/                       # Root module
│   ├── main.tf                 # Module composition
│   ├── variables.tf            # Input variables
│   ├── locals.tf               # Cluster type detection
│   ├── versions.tf             # Provider configuration
│   ├── outputs.tf              # Exported values
│   ├── flux.tf                 # Flux bootstrap configuration
│   ├── terraform.tfvars.example # Identity config template
│   └── tfvars/
│       └── dev.tfvars          # Environment config
│
└── modules/
    └── kind-cluster/           # Reusable KinD cluster module
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## Configuration Files

| File | Purpose | Committed? |
|------|---------|------------|
| `tfvars/dev.tfvars` | Environment config (k8s version, worker count) | Yes |
| `terraform.tfvars.example` | Template for identity config | Yes |
| `terraform.tfvars` | Your GitHub username/repo (copy from example) | No |
| `../.env` | GitHub token | No |

## Variables

| Name | Type | Description | Source |
|------|------|-------------|--------|
| `env` | string | Environment (`dev` or `prod`) | tfvars |
| `cluster_type` | string | Cluster type (`services` or `workloads`) | CLI |
| `cluster_name` | string | Full cluster name (e.g., `services-dev`) | CLI |
| `kubernetes_version` | string | Kubernetes version | tfvars |
| `worker_node_count` | number | Number of worker nodes | tfvars |
| `github_owner` | string | GitHub username or org | terraform.tfvars |
| `github_repository` | string | GitHub repo name | terraform.tfvars |
| `github_token` | string | GitHub PAT (sensitive) | .env |

## Manual Terraform Commands

If you prefer running Terraform directly (from `terraform/main/`):

```bash
# Set token
export TF_VAR_github_token=ghp_xxx

# Initialize
terraform init

# Plan
terraform plan \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"

# Apply
terraform apply \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"

# Destroy
terraform destroy \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"
```

## Flux Bootstrap

Terraform automatically bootstraps Flux after creating the cluster. Flux:

1. Installs controllers (source, kustomize, helm, notification)
2. Commits its manifests to `kubernetes/clusters/{env}/{type}/flux-system/`
3. Starts watching that path for changes

### Verify Flux

```bash
# Check pods
kubectl get pods -n flux-system

# Check sync status
kubectl get kustomizations -n flux-system
```

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | Name of the created cluster |
| `cluster_endpoint` | Kubernetes API server endpoint |
| `kustomize_path` | Path to Kubernetes manifests for this cluster |

## Cluster Types

| Type | Purpose |
|------|---------|
| `services` | Platform services (ingress, cert-manager, argocd) |
| `workloads` | Application workloads (batch-jobs, data-processing) |

## Port Mappings

| Host Port | Container Port | Use Case |
|-----------|---------------|----------|
| 80 | 30080 | HTTP NodePort services |
| 443 | 30443 | HTTPS NodePort services |
