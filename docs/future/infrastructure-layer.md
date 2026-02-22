# Future: infrastructure/ Layer

## Why This Is Deferred

The `infrastructure/` layer is a valid pattern from fleet-infra, but it doesn't add visible functionality right now. Higher-priority additions (kube-prometheus-stack, Calico network policies) were chosen first. Revisit this once there are more namespaces and workloads that need governing.

## What It Is

In fleet-infra, `base/infrastructure/` contains **CRD instances that configure what installed tools do** — as opposed to `apps/base/` which installs the tools themselves.

| Layer | Path | Purpose |
|---|---|---|
| Apps | `apps/base/{tool}/` | HelmReleases that install controllers/operators |
| Infrastructure | `infrastructure/base/` | CRD instances and cluster primitives those tools consume |

In fleet-infra specifically, `base/infrastructure/` contains Karpenter `NodePool` and `EC2NodeClass` objects — the autoscaler config that Karpenter (installed via `apps/base/karpenter/`) reads.

## KinD Equivalent

Karpenter is EKS-specific and doesn't apply to KinD. The equivalent cluster primitives for KinD are:

### PriorityClass
Controls scheduling priority when nodes are under resource pressure.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: platform-high
value: 1000
globalDefault: false
description: "Priority for platform infrastructure components"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: workload-default
value: 0
globalDefault: true
description: "Default priority for workloads"
```

### ResourceQuota (per namespace)
Caps CPU and memory per namespace to prevent one tool from starving others.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: localstack-quota
  namespace: localstack
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 1Gi
    limits.cpu: "4"
    limits.memory: 2Gi
```

Apply similar quotas for `external-secrets` and `crossplane-system`.

### LimitRange (per namespace)
Sets default container resource requests/limits so pods without explicit values get sensible defaults.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: localstack
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
```

## Directory Structure

```
kubernetes/
├── infrastructure/
│   └── base/
│       ├── kustomization.yaml
│       ├── priority-classes.yaml     # PriorityClass: platform-high, workload-default
│       ├── resource-quotas.yaml      # ResourceQuota per namespace
│       └── limit-ranges.yaml         # LimitRange per namespace
└── clusters/dev/services/
    ├── infrastructure.yaml           # Flux Kustomization CRD (new)
    └── kustomization.yaml            # add infrastructure.yaml to resources
```

## Flux Kustomization CRD

Follows the same fleet-infra pattern: `infrastructure-components` has its own Flux Kustomization CRD with `dependsOn` the app CRDs whose namespaces it governs.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./kubernetes/infrastructure/base
  prune: true
  wait: true
  dependsOn:
    - name: localstack
    - name: external-secrets
    - name: crossplane-provider-aws
```

## Fleet-Infra Comparison

| Fleet-Infra (`base/infrastructure/`) | KinD Equivalent |
|---|---|
| Karpenter `NodePool` objects | `PriorityClass` objects |
| Karpenter `EC2NodeClass` objects | `LimitRange` per namespace |
| `ExternalSecret` for cluster credentials | `ResourceQuota` per namespace |
| `dependsOn: karpenter, traefik-config` | `dependsOn: localstack, external-secrets, crossplane-provider-aws` |

## When To Implement

Good time to add this when:
- Calico is added — `NetworkPolicy` objects fit naturally in the infrastructure layer
- More namespaces exist and resource governance becomes useful
- You want to practice PriorityClass behaviour under node pressure
