# OpenShell Sandbox Platform — Phase 1 (control plane)

Stands up a **sandbox-as-a-service control plane**: a governed gateway that provisions isolated,
policy-controlled sandbox environments for AI agents to run in. Phase 1 deploys the control plane and
proves one sandbox can be created → used → destroyed. Guardrails, agent consumers, and policies are
later phases.

---

## What it is — two layers

| Layer | What | Ships as | Installed via |
|---|---|---|---|
| **agent-sandbox** | `Sandbox` CRD + controller (turns a `Sandbox` resource into a pod) | raw manifest (CRD + Deployment + RBAC) | Flux **Kustomization** |
| **OpenShell gateway** | control plane: policy, auth, the `openshell` CLI/gRPC API | Helm chart (OCI) | Flux **HelmRelease** |

```
openshell (HelmRelease)  ──dependsOn──►  agent-sandbox (Kustomization)
   gateway: policy/auth/CLI                 Sandbox CRD + controller → provisions sandbox pods
```

- **agent-sandbox** is a kubernetes-sigs (SIG Apps) project. It adds a `Sandbox` primitive — "one
  isolated, stateful pod with a stable identity" — the building block Kubernetes lacked for agent
  runtimes / dev environments. Vendored at **v0.5.0** (`apps/base/agent-sandbox/manifest.yaml`),
  pinned and reviewable rather than fetched from a URL at apply time.
- **OpenShell** (NVIDIA, public OSS) is the control plane *on top* of agent-sandbox — it adds policy
  enforcement, auth, mTLS, and the `openshell` CLI. Chart pinned at **0.0.69**
  (`oci://ghcr.io/nvidia/openshell`).

### Why one is a manifest and the other a chart
agent-sandbox is fixed plumbing (a controller + CRD) with little to configure → a raw manifest is the
simplest distribution. OpenShell has many knobs (compute driver, TLS, DB, auth, images) → a Helm chart
exposes them as values. Flux applies manifests via `Kustomization` and charts via `HelmRelease`.

---

## Configuration notes

The OpenShell chart's **defaults are built for local use**, so we override almost nothing:
- StatefulSet + SQLite (PVC binds via KinD's `local-path` StorageClass) — default.
- Auto-generated mTLS PKI whose server cert already includes `localhost` / `127.0.0.1` /
  `host.docker.internal` SANs — default (works through `kubectl port-forward`).
- A built-in `NetworkPolicy` restricting sandbox SSH ingress to the gateway — default, and **now
  actually enforced because Calico is the CNI**.
- The only override: `server.auth.allowUnauthenticatedUsers: true` — skips OIDC for local dev.

**Compute driver:** OpenShell uses agent-sandbox as its Kubernetes compute driver → sandboxes are
**pods** (container-grade isolation). OpenShell also supports MicroVM drivers for VM-grade isolation,
but that needs `/dev/kvm`, which KinD (nodes are containers) can't provide. The control-plane
architecture is the lesson here; the isolation backend is a pluggable detail.

**Experimental:** both layers are young (agent-sandbox v0.5.0, OpenShell 0.0.69) and NVIDIA marks the
chart "do not use in production — values change between releases." Expect version churn on upgrades.

---

## Verification (after `make dev-services` / reconcile)

```bash
# 1. agent-sandbox controller up
kubectl get crd sandboxes.agents.x-k8s.io
kubectl get pods -n agent-sandbox-system          # agent-sandbox-controller Running

# 2. OpenShell gateway up
kubectl get pods -n openshell                      # gateway Running
kubectl get kustomizations -A                      # agent-sandbox + openshell READY=True

# 3. Drive it end-to-end with the openshell CLI (install per NVIDIA docs)
kubectl -n openshell port-forward svc/openshell 8080:8080
openshell sandbox create -- bash                   # a Sandbox + pod appear
openshell sandbox exec -n <name> -- echo hello     # or: openshell sandbox connect <name>
openshell sandbox delete <name>                    # pod is torn down
```

---

## Next phases
- **Phase 2** — guardrails: Calico default-deny + egress allowlist + LimitRange/ResourceQuota on the
  sandbox namespace.
- **Phase 3** — first real consumer: Claude Code (`openshell sandbox create -- claude`), Anthropic key
  brokered via ESO.
- **Phase 4** — a second consumer + OpenShell declarative policies; cert-manager for real PKI;
  CloudNativePG for the gateway DB at scale.

---

## References
- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) · [k8s setup](https://docs.nvidia.com/openshell/kubernetes/setup) · [manage sandboxes](https://docs.nvidia.com/openshell/sandboxes/manage-sandboxes)
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
