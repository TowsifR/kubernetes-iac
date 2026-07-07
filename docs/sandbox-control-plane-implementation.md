# Sandbox Control Plane — `kind: Sandbox`

The flagship. A **custom platform API**: users declare a `Sandbox`, and the control plane reconciles a
governed, isolated environment for it. Built as a Crossplane Composition over the `agent-sandbox`
primitive, rendered with KCL, applied by `provider-kubernetes`.

> The control plane is the product. `kubectl apply -f sandbox.yaml` → a governed bundle, reconciled and
> garbage-collected as one unit.

---

## The API

A namespaced claim, deliberately small:

```yaml
apiVersion: platform.example.io/v1alpha1
kind: Sandbox
metadata:
  name: alice-dev-1        # identity → namespace sandbox-alice-dev-1
  namespace: default
spec:
  owner: alice             # attribution: stamped as a label; a governance hook
  size: small              # small|medium|large → scales the ResourceQuota (default: small)
  image: busybox:1.36      # runtime image, allowlisted by policy (default)
status:
  namespace: sandbox-alice-dev-1   # the control plane reports back where it landed
```

Defined by an **XRD** (`definition.yaml`): claim `Sandbox` (namespaced) ↔ composite `XSandbox`
(cluster-scoped), the same split as PVC↔PV — the claim is the user-facing handle, the composite is what
the Composition actually reconciles.

**Identity vs. attribution.** The namespace is keyed off the sandbox's **name** (`sandbox-<name>`), not
its owner — so one owner can hold a *fleet* of sandboxes. `owner` is attribution: a label on the bundle
and a hook for policy, not part of the identity.

## What one claim produces

The Composition (`composition.yaml`) expands a claim into a **guardrailed bundle**, all keyed off
`owner`:

| Resource | Why |
|---|---|
| `Namespace` `sandbox-<name>` | tenant boundary (labeled with `owner`) |
| `ResourceQuota` | caps total pods/CPU/memory — **scaled by `size`** |
| `LimitRange` | per-container defaults + ceilings (fixed, independent of tier) |
| `NetworkPolicy` (default-deny-ingress) | isolation, enforced by Calico |
| `Sandbox` (agent-sandbox) | the actual runtime pod, running `spec.image` |

Design note: the `LimitRange` defaults are what let a resource-less pod (the agent-sandbox busybox)
satisfy the `ResourceQuota` — without defaults, an unspecified request is rejected by the quota.

## How it's wired

```
kubectl apply Sandbox (claim)
   └─ XSandbox (composite)
        └─ Composition  (mode: Pipeline)
             ├─ step render → function-kcl        renders 5 provider-kubernetes Objects
             └─ step ready  → function-auto-ready  marks the XR ready when they are
                  └─ each Object → provider-kubernetes applies a real manifest to the cluster
```

**Why `provider-kubernetes`.** Crossplane only reconciles *managed resources*. `provider-kubernetes`'s
`Object` is a managed resource that carries an arbitrary manifest — so it's the bridge that lets a
Composition create plain Kubernetes objects (namespaces, quotas, CRs) instead of only cloud resources.

**Why KCL renders it.** The five manifests all need the same `Object` wrapper and the same
`owner`-derived namespace. KCL (`function-kcl`) computes the namespace once and loops the wrapper over
the manifests — versus `function-patch-and-transform`, which had to repeat the wrapper five times and
re-inject the namespace via a per-resource patch. See the composition source; ~80 lines vs ~140.

**Provider auth — `InjectedIdentity`.** Unlike `provider-aws` (which authenticates to an external
cloud), `provider-kubernetes` is a client of *this* cluster. The `ProviderConfig`
(`providerconfig.yaml`) uses `InjectedIdentity` → the provider acts as its own ServiceAccount. A
`DeploymentRuntimeConfig` pins that SA's name so a `ClusterRoleBinding` (`provider.yaml`) can grant it
the RBAC to create namespaces/quotas/etc.

## Flux wiring

```
crossplane-provider-kubernetes (Kustomization)   installs provider + function-kcl + function-auto-ready
        └─ dependsOn ─┐
sandbox-platform (Kustomization)                 XRD + Composition + ProviderConfig
        └─ dependsOn: agent-sandbox              (the Sandbox CRD the Composition creates)
```

## Verification (after reconcile)

```bash
kubectl get providers                              # provider-kubernetes  INSTALLED/HEALTHY
kubectl get functions                              # function-kcl, function-auto-ready  HEALTHY
kubectl get xrd                                    # xsandboxes.platform.example.io  ESTABLISHED

kubectl apply -f - <<'EOF'
apiVersion: platform.example.io/v1alpha1
kind: Sandbox
metadata: { name: alice-dev-1, namespace: default }
spec: { owner: alice, size: small }
EOF

kubectl get sandbox alice-dev-1                     # the claim (the API is the product)
kubectl get sandbox alice-dev-1 -o jsonpath='{.status.namespace}'   # → sandbox-alice-dev-1
kubectl get ns sandbox-alice-dev-1                  # bundle landed
kubectl get resourcequota,limitrange,networkpolicy -n sandbox-alice-dev-1
kubectl get pods -n sandbox-alice-dev-1             # agent-sandbox runtime pod Running
kubectl delete sandbox alice-dev-1                  # whole bundle garbage-collected
```

**KCL is verify-on-cluster.** kustomize treats the KCL `source` as an opaque string; it only compiles
inside the `function-kcl` pod. If a claim doesn't reconcile, check `kubectl -n crossplane-system logs`
on the `function-kcl` pod and `kubectl describe xsandbox`.

---

## Relationship to OpenShell

This control plane is *ours*. The [OpenShell detour](openshell-sandbox-implementation.md) is what
surfaced the `agent-sandbox` primitive underneath it — OpenShell is a ready-made gateway; the point of
the portfolio is to **build** the control plane, not install someone else's.

## Roadmap

- **Governance** — Kyverno admission policies on the claim: enforce the `image` allowlist, constrain
  `size`, require/validate the `owner` label.
- **Orchestration** — Temporal for durable lifecycle (provision → ready → TTL cleanup); this is when a
  `ttl` field earns its place on the API.
- **Access** — a task-runner interface; flagship: run an AI agent inside the sandbox.

## References
- [Crossplane Compositions](https://docs.crossplane.io/latest/concepts/compositions/) ·
  [function-kcl](https://github.com/crossplane-contrib/function-kcl) ·
  [provider-kubernetes](https://github.com/crossplane-contrib/provider-kubernetes)
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
