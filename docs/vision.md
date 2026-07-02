# Vision & North Star

## What this is

A **platform-engineering portfolio project**: a self-service, governed **sandbox platform for AI
agents**, built *control-plane-up* on a local Kubernetes (KinD) cluster with production-grade tooling.

It is deliberately **not about the agent** — anyone can `pip install` a sandbox library. It's about the
**platform**: the control plane, governance, and orchestration that turn *"I want a sandbox"* into a
governed, observable, reconciled reality.

> **The control plane is the product. The runtime is commodity.**

- **Audience:** platform-engineering reviewers (hiring managers, peers).
- **"Done" =** a *coherent, working, well-documented, demoable* platform — not a pile of half-built
  phases. A focused system that actually works end-to-end beats a sprawling unfinished one.

## Breadth × depth

- **Breadth** — the whole platform is built to platform-engineering best practices, and **each layer is
  a first-class demonstration in its own right**: IaC, GitOps, observability/monitoring, secrets
  management, network security. (The monitoring stack isn't substrate — it's a standalone competency on
  display.)
- **Depth** — the **agent sandbox control plane** is the flagship: a custom platform API + governance +
  durable orchestration over a *fleet* of sandboxes. This is where the advanced, differentiated skill
  lives.

## Architecture — the planes

```
            ┌──────────────────────────────────────────────────────┐
 interaction│   kubectl apply  ·  (optional) thin self-service UI   │
            └───────────────────────────┬──────────────────────────┘
                                        │  kind: Sandbox
   ┌────────────────────────────────────▼──────────────────────────┐   ┌──────────────┐
   │  CONTROL PLANE                                                 │   │ Observability│
   │   governance   Kyverno — policy-as-code, enforced at admission │   │  Prometheus  │
   │   api/compose  kind: Sandbox  (Crossplane Composition/operator)│   │  Grafana     │
   │   orchestrate  Temporal — durable sandbox/agent lifecycle      │   │  Loki        │
   └────────────────────────────────────┬──────────────────────────┘   ├──────────────┤
   ┌────────────────────────────────────▼──────────────────────────┐   │ Security     │
   │  RESOURCE PLANE   Crossplane (+ provider-kubernetes)           │   │  ESO         │
   │  DATA PLANE       agent-sandbox  (Template · WarmPool · pods)  │   │  Calico/     │
   └────────────────────────────────────┬──────────────────────────┘   │  NetworkPol  │
   ┌────────────────────────────────────▼──────────────────────────┐   │              │
   │  FOUNDATION   Terraform/KinD  ·  Flux GitOps                   │   │ (span all)   │
   └────────────────────────────────────────────────────────────────┘   └──────────────┘
```

| Plane | Tool | Status |
|---|---|---|
| Foundation | Terraform/KinD + Flux GitOps | ✅ |
| Observability | kube-prometheus-stack + Loki/Alloy | ✅ |
| Security | External Secrets + Calico | ✅ |
| Resource control plane | Crossplane (+ `provider-kubernetes`) | ✅ Crossplane · ⏳ provider-kubernetes |
| Data plane (runtime) | agent-sandbox (`SandboxTemplate` · `SandboxWarmPool`) | ✅ installed (via the OpenShell detour) |
| **Sandbox control plane** | `kind: Sandbox` (Crossplane Composition/operator) | ⏳ **flagship** |
| **Governance** | Kyverno (policy-as-code) | ⏳ |
| **Orchestration** | Temporal (durable lifecycle workflows) | ⏳ |

## What it demonstrates

**Foundation competencies (breadth — each a standalone skill):**
- Infrastructure-as-Code (Terraform, reusable modules, cluster bootstrap)
- GitOps (Flux: HelmReleases, Kustomizations, `dependsOn` ordering)
- Observability (Prometheus/Grafana metrics, Loki/Alloy logs → object storage)
- Secrets management (External Secrets Operator)
- Network security (Calico-enforced NetworkPolicy)
- Cloud-resource provisioning as code (Crossplane → object storage)

**Flagship competencies (depth):**
- Building a **custom control plane / platform API** (Crossplane Compositions / operator pattern)
- **Policy-as-code governance** (Kyverno admission control)
- **Durable orchestration** (Temporal lifecycle workflows)
- **Fleet/lifecycle management** (templates, warm pools, reconciliation)
- Control-plane / data-plane separation

**Scale-awareness (a senior signal):** these patterns are demonstrated at KinD scale; at real scale
you'd add a custom VM/sandbox scheduler, multi-cluster fleet management, and high-availability durable
execution. Knowing *what changes* at scale is part of the point.

## The spine / demo flow

```bash
kubectl apply -f my-sandbox.yaml      # kind: Sandbox { owner, size, ttl }
#   → Kyverno admits it (owner present? size within policy?)
#   → the control plane reconciles a governed bundle:
#       namespace · ResourceQuota · LimitRange · NetworkPolicy · agent-sandbox Sandbox
#   → Temporal owns the lifecycle (provision → ready → ttl cleanup)
kubectl get sandboxes                 # the API is the product
kubectl delete sandbox my-sandbox     # whole bundle garbage-collected
```

## Roadmap to demoable

- [x] **Foundation** — Terraform/KinD, Flux, LocalStack, ESO, Crossplane→object storage
- [x] **Observability** — kube-prometheus-stack, Loki + Alloy
- [x] **Ingress & network security** — Traefik, Calico
- [x] **OpenShell** (Phase 1) — the learning detour that surfaced the agent-sandbox primitive
- [ ] **Sandbox control plane** — `provider-kubernetes` + `kind: Sandbox` Composition over agent-sandbox
- [ ] **Governance** — Kyverno policies on `Sandbox`
- [ ] **Orchestration** — Temporal durable lifecycle workflows
- [ ] **Polish** — architecture diagram, demo recording, README story
- [ ] *(optional)* **Thin UI** — a self-service client over the `Sandbox` API

## Non-goals
- Not web-scale (no custom VM scheduler, no 100k-sandbox fleet).
- Not multi-tenant production or a real hosted service.
- Not a novel agent — the agent/runtime is intentionally commodity.
