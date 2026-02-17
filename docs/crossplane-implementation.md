# Crossplane Implementation Plan

## Overview

Crossplane manages AWS resources (S3 buckets, DynamoDB tables, etc.) via Kubernetes CRDs. The AWS provider points at LocalStack instead of real AWS, allowing us to learn Crossplane without cloud costs.

This mirrors the production pattern at `oneai-core-fleet-infra/apps/base/crossplane/`.

## Dependency Chain

Crossplane has strict ordering requirements — CRDs must exist before resources that use them can be applied. We use Flux Kustomization CRDs with `dependsOn` to enforce this.

```
crossplane-base (HelmRelease installs Crossplane + CRDs)
       ↓ dependsOn
crossplane-config (Provider package: crossplane-contrib/provider-aws:v0.48.0)
       ↓ dependsOn
crossplane-provider-aws (Secret with test/test creds + ProviderConfig → LocalStack endpoint)
```

## Differences from Fleet-Infra

| Fleet-Infra | This Repo |
|---|---|
| IRSA (InjectedIdentity) | Static Secret (test/test for LocalStack) |
| DeploymentRuntimeConfig (node affinity, IRSA) | Skipped (no labeled nodes in KinD) |
| AWS + Tencent providers | AWS only |
| `${CROSSPLANE_CHART_VERSION}` variable | Hardcoded `1.18.*` |
| Corporate CA bundle (cert-cm.yaml) | Skipped |
| ProviderConfig endpoint: Dynamic → amazonaws.com | Static → `http://localstack.localstack.svc.cluster.local:4566` |

## Directory Structure

```
kubernetes/
├── apps/base/
│   └── crossplane/
│       ├── crossplane-base/
│       │   ├── kustomization.yaml
│       │   ├── namespace.yaml          # crossplane-system namespace
│       │   ├── helmrepository.yaml     # charts.crossplane.io/stable
│       │   └── helmrelease.yaml        # crossplane chart 1.18.*
│       ├── crossplane-config/
│       │   ├── kustomization.yaml
│       │   └── provider.yaml           # crossplane-contrib/provider-aws:v0.48.0
│       └── provider-aws/
│           ├── kustomization.yaml
│           ├── credentials.yaml        # Secret with test/test (LocalStack default)
│           └── provider-config.yaml    # ProviderConfig → LocalStack endpoint
└── clusters/dev/services/
    ├── crossplane-base.yaml            # Flux Kustomization CRD
    ├── crossplane-config.yaml          # Flux Kustomization CRD, dependsOn: crossplane-base
    └── crossplane-provider-aws.yaml    # Flux Kustomization CRD, dependsOn: crossplane-config
```

### Why Flux Kustomization CRDs?

Crossplane is **not** added to `apps/base/kustomization.yaml` like LocalStack is. Instead, each stage has its own Flux Kustomization CRD in `clusters/dev/services/`. This is because:

1. The `Provider` CRD (`pkg.crossplane.io/v1`) doesn't exist until the Crossplane Helm chart installs it
2. The `ProviderConfig` CRD (`aws.crossplane.io/v1beta1`) doesn't exist until the Provider package installs it
3. Flux Kustomization CRDs with `dependsOn` ensure each stage waits for the previous one to be ready

A flat Kustomize build would try to apply everything at once and fail.

## Components

### crossplane-base

Installs the Crossplane control plane via Helm:
- **Chart:** `crossplane` from `https://charts.crossplane.io/stable`
- **Version:** `1.18.*`
- **Namespace:** `crossplane-system`
- Registers `pkg.crossplane.io` CRDs (Provider, DeploymentRuntimeConfig, etc.)

### crossplane-config

Installs the AWS provider package:
- **Package:** `xpkg.upbound.io/crossplane-contrib/provider-aws:v0.48.0`
- Same provider version as fleet-infra
- Once healthy, registers `aws.crossplane.io` CRDs (Bucket, Key, ProviderConfig, etc.)

### provider-aws

Configures how Crossplane authenticates and connects to AWS (LocalStack):
- **Credentials:** Static Secret with `aws_access_key_id=test`, `aws_secret_access_key=test`
- **Endpoint:** `http://localstack.localstack.svc.cluster.local:4566` (Static, with `hostnameImmutable: true`)
- **ProviderConfig name:** `default` — any Crossplane resource without an explicit `providerConfigRef` uses this automatically

## Verification

```bash
# Flux Kustomizations should show Ready
kubectl get kustomizations -n flux-system

# Crossplane pods running
kubectl get pods -n crossplane-system

# Provider healthy
kubectl get providers

# ProviderConfig exists
kubectl get providerconfig default -o yaml
```

## Usage Example

Once deployed, create AWS resources via Kubernetes manifests:

```yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: my-app-data
spec:
  forProvider:
    locationConstraint: us-east-1
  # No providerConfigRef needed — uses "default" ProviderConfig automatically
```

Commit this to git → Flux applies it → Crossplane creates the bucket in LocalStack.

## Future Evolution

- Add `environment.env` + ConfigMap variable substitution (like fleet-infra's `cluster-vars`)
- Add more providers if needed
- Add Crossplane Compositions for reusable resource templates
- Switch to real AWS by changing the ProviderConfig endpoint and credentials
