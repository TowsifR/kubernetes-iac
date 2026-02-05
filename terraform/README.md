# Terraform - KinD Cluster Creation

This Terraform configuration creates local Kubernetes clusters using [KinD (Kubernetes in Docker)](https://kind.sigs.k8s.io/). It mirrors patterns from production EKS infrastructure, providing a cost-free learning environment.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Directory Structure

```
terraform/
├── main/                       # Root module - entry point
│   ├── main.tf                 # Module composition
│   ├── variables.tf            # Input variables
│   ├── locals.tf               # Cluster type detection logic
│   ├── versions.tf             # Provider configuration
│   ├── outputs.tf              # Exported values
│   └── tfvars/
│       ├── dev.tfvars          # Dev environment defaults
│       └── prod.tfvars         # Prod environment defaults
│
└── modules/
    └── kind-cluster/           # Reusable KinD cluster module
        ├── main.tf             # KinD cluster resource
        ├── variables.tf        # Module inputs
        ├── outputs.tf          # Module outputs
        └── versions.tf         # Required providers
```

## Usage

All commands run from `terraform/main/`:

```bash
cd terraform/main
```

### Initialize

```bash
terraform init
```

### Plan

Preview what will be created:

```bash
# Services cluster (dev)
terraform plan \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"

# Workloads cluster (dev)
terraform plan \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=workloads-dev" \
  -var="cluster_type=workloads"
```

### Apply

Create the cluster:

```bash
terraform apply \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"
```

### Destroy

Tear down the cluster:

```bash
terraform destroy \
  -var-file="tfvars/dev.tfvars" \
  -var="cluster_name=services-dev" \
  -var="cluster_type=services"
```

## Variables

| Name | Type | Description | Required |
|------|------|-------------|----------|
| `env` | string | Environment (`dev` or `prod`) | Yes |
| `cluster_type` | string | Cluster type (`services` or `workloads`) | Yes |
| `cluster_name` | string | Full cluster name (e.g., `services-dev`) | Yes |
| `kubernetes_version` | string | Kubernetes version for nodes | No (default in tfvars) |
| `worker_node_count` | number | Number of worker nodes | No (default in tfvars) |
| `common_labels` | map(string) | Labels applied to resources | No |

### Environment Defaults (tfvars)

**dev.tfvars:**
- `kubernetes_version`: v1.32.2
- `worker_node_count`: 1

**prod.tfvars:**
- `kubernetes_version`: v1.28.7
- `worker_node_count`: 2

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | Name of the created cluster |
| `cluster_endpoint` | Kubernetes API server endpoint |
| `kubeconfig_path` | Path to the generated kubeconfig file |
| `kustomize_path` | Path to Kubernetes manifests for this cluster |

## Cluster Types

This setup supports two cluster types, mirroring production patterns:

| Type | Purpose | Namespaces (via Kustomize) |
|------|---------|---------------------------|
| `services` | Platform services, ingress, GitOps | ingress-nginx, cert-manager, argocd |
| `workloads` | Application workloads, batch jobs | batch-jobs, data-processing, argo-workflows |

## Port Mappings

The control-plane node maps these ports for accessing services:

| Host Port | Container Port | Use Case |
|-----------|---------------|----------|
| 80 | 30080 | HTTP NodePort services |
| 443 | 30443 | HTTPS NodePort services |

## Verify Cluster

After apply, verify the cluster is running:

```bash
# Check cluster exists
kind get clusters

# Check nodes are ready
kubectl get nodes

# Check kubectl context
kubectl config current-context
```

