# Local Infrastructure Learning Project

A monorepo learning environment that mirrors patterns from both `oneai-core-infra` (Terraform) and `oneai-core-fleet-infra` (Flux/Helm) using KinD locally.

## Overview

This project teaches enterprise infrastructure patterns without cloud costs:

| Production Repos | What They Do | Learning Project |
|------------------|--------------|------------------|
| `oneai-core-infra` | Terraform creates EKS clusters | `terraform/` creates KinD clusters |
| `oneai-core-fleet-infra` | Flux/Helm deploys apps into clusters | `kubernetes/` deploys apps with Kustomize |

### Why Monorepo for Learning?

- **See the full picture** - Understand how infra creation connects to app deployment
- **Atomic changes** - Update cluster config + apps in one PR
- **Simpler** - One place, one workflow
- **Split later** - Easy to separate once you understand the patterns

---

## Project Structure

```
local-infra-learning/
│
├── terraform/                      # Cluster creation (mirrors oneai-core-infra)
│   ├── main/
│   │   ├── main.tf                # Module composition
│   │   ├── variables.tf
│   │   ├── locals.tf              # Cluster type detection
│   │   ├── versions.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf
│   │   └── tfvars/
│   │       ├── dev.tfvars
│   │       └── prod.tfvars
│   └── modules/
│       └── kind-cluster/
│           ├── main.tf            # KinD cluster resource
│           ├── variables.tf
│           ├── locals.tf
│           └── outputs.tf
│
├── kubernetes/                     # App deployment (mirrors oneai-core-fleet-infra)
│   ├── apps/                      # Helm charts / app manifests
│   │   ├── base/                  # Shared app configs
│   │   │   ├── nginx/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   ├── namespace.yaml
│   │   │   │   ├── deployment.yaml
│   │   │   │   └── service.yaml
│   │   │   ├── prometheus/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── helmrelease.yaml
│   │   │   └── kustomization.yaml
│   │   └── README.md
│   │
│   ├── infrastructure/            # Cluster-level resources
│   │   ├── base/
│   │   │   ├── namespaces.yaml
│   │   │   ├── resource-quotas.yaml
│   │   │   └── kustomization.yaml
│   │   ├── services/              # Services cluster overlay
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   └── workloads/             # Workloads cluster overlay
│   │       ├── kustomization.yaml
│   │       └── patches/
│   │
│   └── clusters/                  # Environment configs (mirrors clusters/stages/)
│       ├── dev/
│       │   ├── services/
│       │   │   ├── kustomization.yaml
│       │   │   └── environment.env
│       │   └── workloads/
│       │       ├── kustomization.yaml
│       │       └── environment.env
│       └── prod/
│           ├── services/
│           │   ├── kustomization.yaml
│           │   └── environment.env
│           └── workloads/
│               ├── kustomization.yaml
│               └── environment.env
│
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml     # Terraform CI
│       ├── terraform-apply.yml
│       └── kustomize-validate.yml # Kubernetes CI
│
├── Makefile                       # Unified commands
└── README.md
```

---

## Part 1: Terraform (Cluster Creation)

*Mirrors patterns from `oneai-core-infra`*

### terraform/main/versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "kind" {}

provider "kubernetes" {
  host                   = module.kind-cluster.cluster_endpoint
  cluster_ca_certificate = module.kind-cluster.cluster_ca_certificate
  client_certificate     = module.kind-cluster.client_certificate
  client_key             = module.kind-cluster.client_key
}

provider "helm" {
  kubernetes {
    host                   = module.kind-cluster.cluster_endpoint
    cluster_ca_certificate = module.kind-cluster.cluster_ca_certificate
    client_certificate     = module.kind-cluster.client_certificate
    client_key             = module.kind-cluster.client_key
  }
}
```

### terraform/main/variables.tf

```hcl
variable "env" {
  type        = string
  description = "Environment (dev, prod)"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "Must be 'dev' or 'prod'."
  }
}

variable "cluster_type" {
  type        = string
  description = "Cluster type (services, workloads)"
  validation {
    condition     = contains(["services", "workloads"], var.cluster_type)
    error_message = "Must be 'services' or 'workloads'."
  }
}

variable "cluster_name" {
  type        = string
  description = "Full cluster name (e.g., services-dev)"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.29.2"
}

variable "worker_node_count" {
  type    = number
  default = 1
}

variable "common_labels" {
  type = map(string)
  default = {
    "managed-by" = "terraform"
    "project"    = "local-infra-learning"
  }
}
```

### terraform/main/locals.tf

```hcl
# Pattern: Mirrors modules/oneai/tf-eks-base/locals.tf
locals {
  is_services_cluster  = strcontains(var.cluster_type, "services")
  is_workloads_cluster = strcontains(var.cluster_type, "workloads")

  all_labels = merge(var.common_labels, {
    "environment"  = var.env
    "cluster-type" = var.cluster_type
  })
}
```

### terraform/main/main.tf

```hcl
# Pattern: Mirrors main/main.tf → modules/oneai/tf-eks-base
module "kind-cluster" {
  source = "../modules/kind-cluster"

  cluster_name       = var.cluster_name
  cluster_type       = var.cluster_type
  kubernetes_version = var.kubernetes_version
  worker_node_count  = var.worker_node_count
  env                = var.env
  common_labels      = local.all_labels
}
```

### terraform/main/outputs.tf

```hcl
output "cluster_name" {
  value = module.kind-cluster.cluster_name
}

output "kubeconfig_path" {
  value = module.kind-cluster.kubeconfig_path
}

output "cluster_endpoint" {
  value = module.kind-cluster.cluster_endpoint
}

# Output for Kubernetes deployment step
output "kustomize_path" {
  description = "Path to apply Kubernetes manifests"
  value       = "../../kubernetes/clusters/${var.env}/${var.cluster_type}"
}
```

### terraform/modules/kind-cluster/main.tf

```hcl
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

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
```

### terraform/main/tfvars/dev.tfvars

```hcl
env                = "dev"
kubernetes_version = "v1.29.2"
worker_node_count  = 1
```

### terraform/main/tfvars/prod.tfvars

```hcl
env                = "prod"
kubernetes_version = "v1.28.7"
worker_node_count  = 2
```

---

## Part 2: Kubernetes (App Deployment)

*Mirrors patterns from `oneai-core-fleet-infra`*

### Kustomize Layer Pattern

```
kubernetes/
├── apps/base/           # App definitions (like apps/base/ in fleet-infra)
├── infrastructure/      # Cluster resources (like base/infrastructure/)
│   ├── base/           # Shared across all clusters
│   ├── services/       # Services cluster overlay
│   └── workloads/      # Workloads cluster overlay
└── clusters/           # Environment configs (like clusters/stages/)
    ├── dev/
    └── prod/
```

### kubernetes/infrastructure/base/kustomization.yaml

```yaml
# Pattern: Mirrors base/infrastructure/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespaces.yaml
  - resource-quotas.yaml
```

### kubernetes/infrastructure/base/namespaces.yaml

```yaml
# Base namespaces created for ALL clusters
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    purpose: observability
---
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
  labels:
    purpose: gitops
```

### kubernetes/infrastructure/services/kustomization.yaml

```yaml
# Pattern: Cluster-type specific overlay
# Mirrors: clusters/stages/prod/clusters/services-emea/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../base
  - namespaces.yaml

# Services-specific namespaces
# Pattern: Conditional resources based on cluster type
```

### kubernetes/infrastructure/services/namespaces.yaml

```yaml
# Services cluster gets platform namespaces
# Pattern: Mirrors is_service_cluster conditional in Terraform
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
  labels:
    cluster-type: services
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    cluster-type: services
---
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    cluster-type: services
```

### kubernetes/infrastructure/workloads/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../base
  - namespaces.yaml
```

### kubernetes/infrastructure/workloads/namespaces.yaml

```yaml
# Workloads cluster gets job namespaces
# Pattern: Mirrors is_factory_cluster conditional
apiVersion: v1
kind: Namespace
metadata:
  name: batch-jobs
  labels:
    cluster-type: workloads
---
apiVersion: v1
kind: Namespace
metadata:
  name: data-processing
  labels:
    cluster-type: workloads
---
apiVersion: v1
kind: Namespace
metadata:
  name: argo-workflows
  labels:
    cluster-type: workloads
```

### kubernetes/clusters/dev/services/kustomization.yaml

```yaml
# Pattern: Mirrors clusters/stages/dev/clusters/services-emea/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../infrastructure/services
  - ../../../apps/base

# Load environment variables
# Pattern: Mirrors configMapGenerator with environment.env
configMapGenerator:
  - name: cluster-config
    namespace: kube-system
    envs:
      - environment.env

# Variable substitution (like Flux postBuild.substituteFrom)
# These vars get injected into manifests
vars:
  - name: CLUSTER_NAME
    objref:
      kind: ConfigMap
      name: cluster-config
      apiVersion: v1
    fieldref:
      fieldpath: data.CLUSTER_NAME
```

### kubernetes/clusters/dev/services/environment.env

```bash
# Pattern: Mirrors environment.env in oneai-core-fleet-infra
CLUSTER_NAME=services-dev
CLUSTER_TYPE=services
ENVIRONMENT=dev
LOG_LEVEL=debug
REPLICAS=1
```

### kubernetes/clusters/prod/services/environment.env

```bash
CLUSTER_NAME=services-prod
CLUSTER_TYPE=services
ENVIRONMENT=prod
LOG_LEVEL=info
REPLICAS=2
```

---

## Part 3: Apps with Helm

*Mirrors `apps/base/` in fleet-infra*

### kubernetes/clusters/dev/services/kustomization.yaml

Each app gets its own Flux Kustomization CRD for independent reconciliation and `dependsOn` support.
No flat `apps/base/kustomization.yaml` — each app directory is pointed to directly by a Flux Kustomization CRD file.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - localstack.yaml           # Flux Kustomization CRD → apps/base/localstack/
  - external-secrets.yaml     # Flux Kustomization CRD → apps/base/external-secrets/
  # - my-app.yaml             # Add new apps here
```

### kubernetes/apps/base/nginx/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
```

### kubernetes/apps/base/nginx/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  namespace: nginx-demo
  labels:
    app: nginx-demo
spec:
  replicas: 1  # Can be patched per environment
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
```

### kubernetes/apps/base/prometheus/helmrelease.yaml

```yaml
# Pattern: Mirrors apps/base/kube-prometheus-stack/helmrelease.yaml
# This is a Flux HelmRelease CRD - works with Flux CD
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "55.x"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    grafana:
      enabled: true
      adminPassword: admin  # Don't do this in prod!
    prometheus:
      prometheusSpec:
        retention: 7d
        # Environment-based config
        replicas: 1  # ${REPLICAS} with Flux substitution
```

---

## Part 4: Simulated Karpenter NodePools

*Mirrors `base/infrastructure/*-karpenter-resources.yaml`*

### kubernetes/infrastructure/base/nodepool-configs.yaml

```yaml
# These are ConfigMaps that SIMULATE NodePool configs
# In production, these would be Karpenter NodePool CRDs
# Pattern: Learn the structure without needing Karpenter installed

apiVersion: v1
kind: ConfigMap
metadata:
  name: nodepool-default
  namespace: kube-system
  labels:
    nodepool-type: default
data:
  config: |
    # Simulates default-karpenter-resources.yaml
    instanceTypes:
      - c5.large
      - c5.xlarge
      - m5.large
      - m5.xlarge
    capacityType: on-demand
    consolidation: WhenUnderutilized
    limits:
      cpu: 100
      memory: 200Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodepool-gpu
  namespace: kube-system
  labels:
    nodepool-type: gpu
data:
  config: |
    # Simulates gpu-karpenter-resources.yaml
    instanceTypes:
      - p4d.24xlarge
    capacityType: on-demand
    taints:
      - key: nvidia.com/gpu
        effect: NoSchedule
    limits:
      nvidia.com/gpu: 8
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodepool-infra
  namespace: kube-system
  labels:
    nodepool-type: infra
data:
  config: |
    # Simulates infra-karpenter-resources.yaml
    instanceTypes:
      - c5.large
      - m5.large
    taints:
      - key: infra
        value: "true"
        effect: NoSchedule
    consolidation: WhenEmpty
```

---

## Makefile (Unified Commands)

```makefile
.PHONY: help cluster deploy destroy clean

ENV ?= dev
CLUSTER_TYPE ?= services
CLUSTER_NAME ?= $(CLUSTER_TYPE)-$(ENV)

# Paths
TF_DIR = terraform/main
K8S_DIR = kubernetes/clusters/$(ENV)/$(CLUSTER_TYPE)
STATE_PATH = ./terraform-state/$(ENV)-$(CLUSTER_TYPE).tfstate

help:
	@echo "Local Infrastructure Learning Project"
	@echo ""
	@echo "Usage: make <target> ENV=<env> CLUSTER_TYPE=<type>"
	@echo ""
	@echo "Cluster Lifecycle:"
	@echo "  cluster     - Create KinD cluster with Terraform"
	@echo "  deploy      - Deploy Kubernetes resources with Kustomize"
	@echo "  all         - Create cluster + deploy apps"
	@echo "  destroy     - Destroy everything"
	@echo ""
	@echo "Examples:"
	@echo "  make all ENV=dev CLUSTER_TYPE=services"
	@echo "  make all ENV=dev CLUSTER_TYPE=workloads"

# Step 1: Create cluster with Terraform
cluster:
	@echo "Creating $(CLUSTER_NAME) cluster..."
	cd $(TF_DIR) && terraform init -backend-config="path=$(STATE_PATH)"
	cd $(TF_DIR) && terraform apply \
		-var-file="tfvars/$(ENV).tfvars" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="cluster_type=$(CLUSTER_TYPE)" \
		-auto-approve
	@echo "Cluster created. Setting kubeconfig..."
	kind export kubeconfig --name $(CLUSTER_NAME)

# Step 2: Deploy apps with Kustomize
deploy:
	@echo "Deploying to $(CLUSTER_NAME)..."
	kubectl apply -k $(K8S_DIR)
	@echo ""
	@echo "Deployed! Check resources:"
	@echo "  kubectl get ns"
	@echo "  kubectl get pods -A"

# Combined: cluster + deploy
all: cluster deploy

# Destroy everything
destroy:
	@echo "Destroying $(CLUSTER_NAME)..."
	cd $(TF_DIR) && terraform destroy \
		-var-file="tfvars/$(ENV).tfvars" \
		-var="cluster_name=$(CLUSTER_NAME)" \
		-var="cluster_type=$(CLUSTER_TYPE)" \
		-auto-approve

# Clean up state files
clean:
	rm -rf $(TF_DIR)/.terraform
	rm -rf $(TF_DIR)/terraform-state
	kind delete clusters --all

# Quick shortcuts
dev-services:
	$(MAKE) all ENV=dev CLUSTER_TYPE=services

dev-workloads:
	$(MAKE) all ENV=dev CLUSTER_TYPE=workloads

prod-services:
	$(MAKE) all ENV=prod CLUSTER_TYPE=services

# Validate Kustomize builds
validate:
	@echo "Validating Kustomize builds..."
	kubectl kustomize kubernetes/clusters/dev/services
	kubectl kustomize kubernetes/clusters/dev/workloads
	kubectl kustomize kubernetes/clusters/prod/services
	kubectl kustomize kubernetes/clusters/prod/workloads
	@echo "All builds valid!"
```

---

## GitHub Actions CI/CD

### .github/workflows/terraform-plan.yml

```yaml
name: Terraform Plan

on:
  pull_request:
    paths: ['terraform/**']

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [dev, prod]
        cluster_type: [services, workloads]

    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Plan
        working-directory: terraform/main
        run: |
          terraform init -backend-config="path=./state/${{ matrix.env }}-${{ matrix.cluster_type }}.tfstate"
          terraform plan \
            -var-file="tfvars/${{ matrix.env }}.tfvars" \
            -var="cluster_name=${{ matrix.cluster_type }}-${{ matrix.env }}" \
            -var="cluster_type=${{ matrix.cluster_type }}"
```

### .github/workflows/kustomize-validate.yml

```yaml
name: Validate Kustomize

on:
  pull_request:
    paths: ['kubernetes/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [dev, prod]
        cluster_type: [services, workloads]

    steps:
      - uses: actions/checkout@v4

      - name: Validate Kustomize Build
        run: |
          kubectl kustomize kubernetes/clusters/${{ matrix.env }}/${{ matrix.cluster_type }} > /dev/null
          echo "✓ ${{ matrix.env }}/${{ matrix.cluster_type }} is valid"
```

---

## Quick Start

```bash
# 1. Clone/create the project
mkdir local-infra-learning && cd local-infra-learning

# 2. Create the structure from this document

# 3. Create a services cluster and deploy apps
make all ENV=dev CLUSTER_TYPE=services

# 4. Verify
kubectl get nodes
kubectl get ns
# Should see: monitoring, flux-system, ingress-nginx, cert-manager, argocd

# 5. Destroy and try workloads cluster
make destroy ENV=dev CLUSTER_TYPE=services
make all ENV=dev CLUSTER_TYPE=workloads

kubectl get ns
# Should see: monitoring, flux-system, batch-jobs, data-processing, argo-workflows
```

---

## Pattern Mapping Summary

| Production Pattern | Production Location | Learning Project |
|-------------------|---------------------|------------------|
| **Terraform module composition** | `oneai-core-infra/main/main.tf` | `terraform/main/main.tf` |
| **Cluster type conditionals** | `tf-eks-base/locals.tf` | `terraform/main/locals.tf` + Kustomize overlays |
| **Environment tfvars** | `main/tfvars/*.tfvars` | `terraform/main/tfvars/` |
| **Kustomize base + overlays** | `oneai-core-fleet-infra/base/` | `kubernetes/infrastructure/` |
| **Cluster configs** | `clusters/stages/{env}/clusters/` | `kubernetes/clusters/{env}/` |
| **Environment variables** | `environment.env` files | `kubernetes/clusters/{env}/{type}/environment.env` |
| **HelmRelease CRDs** | `apps/base/*/helmrelease.yaml` | `kubernetes/apps/base/*/helmrelease.yaml` |
| **Karpenter NodePools** | `base/infrastructure/*-karpenter-resources.yaml` | `kubernetes/infrastructure/base/nodepool-configs.yaml` (simulated) |
| **Matrix CI/CD** | `plan_eks_clusters.yml` | Both workflow files |

---

## Extension Ideas

1. **Add Flux CD** - Bootstrap Flux to watch the `kubernetes/` directory ✅ Done
2. **Real HelmReleases** - Install Flux and use actual HelmRelease CRDs ✅ Done
3. **LocalStack** - Emulate AWS services locally (S3, SQS, Secrets Manager, etc.) ✅ Done — see `apps/base/localstack/`
4. **External Secrets Operator** - Sync secrets from LocalStack Secrets Manager into Kubernetes ✅ Done — see `apps/base/external-secrets/` and `docs/localstack-eso-setup.md`
5. **Crossplane** - Provision AWS resources (S3, DynamoDB) via Kubernetes CRDs against LocalStack ✅ Done — see `apps/base/crossplane/` and `docs/crossplane-implementation.md`
6. **Multi-cluster** - Create both services + workloads clusters simultaneously
7. **ArgoCD** - Deploy ArgoCD to services cluster, manage workloads cluster
8. **Network Policies** - Add Calico and enforce namespace isolation
9. **Observability** - Full Prometheus + Grafana + Loki stack

---

## Prerequisites

```bash
# Docker (required for KinD)
brew install --cask docker

# KinD
brew install kind

# Terraform
brew install terraform

# kubectl
brew install kubectl

# Kustomize (usually bundled with kubectl)
brew install kustomize

# Optional: Flux CLI (for GitOps extension)
brew install fluxcd/tap/flux
```

---

## Reference Files

**From oneai-core-infra (Terraform):**
- `main/main.tf` - Module composition
- `modules/oneai/tf-eks-base/locals.tf` - Cluster type detection
- `modules/oneai/tf-eks-base/irsa.tf` - Conditional resources
- `.github/workflows/plan_eks_clusters.yml` - Matrix CI

**From oneai-core-fleet-infra (Flux/Helm):**
- `base/kustomization.yaml` - Root orchestration
- `base/infrastructure/` - NodePool configs
- `clusters/stages/{env}/clusters/{cluster}/kustomization.yaml` - Cluster overlays
- `clusters/stages/{env}/clusters/{cluster}/environment.env` - Environment vars
- `apps/base/kube-prometheus-stack/helmrelease.yaml` - Helm deployment

