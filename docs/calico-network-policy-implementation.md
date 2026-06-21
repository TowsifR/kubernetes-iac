# Calico CNI & Network Policy Implementation

Replaces KinD's default CNI with **Calico** so the cluster can actually *enforce*
`NetworkPolicy`, and explains how we learn network policy from the policies Flux
already ships — without hand-authoring per-app policies.

---

## Why this exists

A `NetworkPolicy` object is only meaningful if the cluster's CNI enforces it.
KinD's default CNI, **kindnet**, gives pods IPs and connectivity but has **no
policy engine** — it accepts `NetworkPolicy` objects and silently ignores them.
So before any policy work is real, the CNI has to be swapped for one that
enforces. We use Calico, a widely-used CNI with a built-in policy engine.

---

## What is a CNI, and what does Calico add?

A **CNI (Container Network Interface)** plugin does two jobs:

1. **Networking** — assign every pod an IP and route pod-to-pod traffic. *(kindnet does this.)*
2. **Policy enforcement** — drop/allow traffic according to `NetworkPolicy`. *(kindnet does NOT.)*

Calico does both. Installing it as `cni.type: Calico` makes it own pod networking
**and** turn `NetworkPolicy` from decoration into enforced firewall rules.

---

## Design decisions

| Aspect | Decision | Why |
|---|---|---|
| **Install method** | tigera-operator Helm chart | Operator-managed install is the standard, supported path for Calico |
| **Where installed** | Terraform, before Flux bootstrap | The CNI must exist before any GitOps-managed pod can schedule |
| **CNI mode** | Calico full CNI (replaces kindnet) | kindnet has no policy engine; Calico owns networking + enforcement |
| **IP pool / encapsulation** | `192.168.0.0/16` / `VXLANCrossSubnet` | Calico's default pool; VXLAN keeps node-to-node pod traffic portable |
| **calico-apiserver** | enabled | Lets us inspect/manage Calico resources via `kubectl` |
| **Chart version** | `v3.30.7` | Current release; supports Kubernetes 1.32 (the cluster version) |
| **Hand-written NetworkPolicies** | none | See below |

> **On not authoring per-app policies:** a common best practice is to *not*
> scatter a `networkpolicy.yaml` into every app. Flux already ships three
> `NetworkPolicy` objects in `flux-system` (`allow-egress`, `allow-scraping`,
> `allow-webhooks`); installing Calico makes those real. We rely on them as the
> worked example rather than adding boilerplate that has to be maintained.

---

## The bootstrap-ordering problem (the important concept)

Disabling kindnet leaves the cluster with **no pod networking at all** until
Calico installs itself. Nothing that needs a pod IP can run in that window — and
**Flux's own controllers are pods**. So the install order is strict:

```
kind_cluster  →  helm_release.calico  →  flux_bootstrap_git
   (no CNI)        (installs CNI)          (needs CNI to schedule pods)
```

Two Terraform details make this work:

- **`wait_for_ready = false`** on the KinD cluster (`terraform/modules/kind-cluster/main.tf`).
  With no CNI, nodes never reach `Ready`; leaving the default `true` would hang the
  apply forever. Calico readiness is handled by the Helm release instead.
- **`depends_on = [..., helm_release.calico]`** on `flux_bootstrap_git`
  (`terraform/main/flux.tf`) — Flux only bootstraps after the CNI is up.

The operator itself can schedule onto a `NotReady` node because the tigera-operator
runs host-networked — it doesn't need the CNI it's about to install (avoiding the
chicken-and-egg deadlock).

---

## What gets installed

`terraform/main/calico.tf` installs the **tigera-operator** Helm chart. The operator
is a controller: Helm installs the operator, then the operator reconciles
`calico-node` / `typha` / `calico-apiserver` from the `Installation` config we pass.

The values use a minimal production-style configuration. A cloud setup would add
a private image registry and node-affinity/tolerations to pin Calico to dedicated
infrastructure nodes; KinD pulls public images and runs a single untainted node,
so neither is needed here:

```yaml
installation:
  cni:
    type: Calico
  calicoNetwork:
    ipPools:
      - cidr: 192.168.0.0/16        # MUST match the KinD pod_subnet
        encapsulation: VXLANCrossSubnet
  controlPlaneReplicas: 1
apiServer:
  enabled: true                     # calico-apiserver: manage/inspect Calico via kubectl
```

### Why `pod_subnet` must match the Calico IP pool

KinD's default `podSubnet` is `10.244.0.0/16` and becomes the cluster's
`--cluster-cidr` (used by kube-proxy, SNAT, node `podCIDR` allocation). Calico's
IPAM hands out pod IPs from its own `ipPool` (`192.168.0.0/16`). If those two
disagree, the cluster is internally inconsistent — routing/masquerade thinks pods
live in one range while they actually live in another. So we set **both** to
`192.168.0.0/16` (`terraform/modules/kind-cluster/main.tf` `pod_subnet` =
`calico.tf` `ipPools.cidr`).

---

## Learning network policy from Flux's built-ins

`flux bootstrap` writes three `NetworkPolicy` objects into `flux-system`
(in the Flux-managed `gotk-components.yaml`). With kindnet they were no-ops; with
Calico they are enforced. They are a compact, production-real example of the
default-deny + selective-allow pattern:

| Policy | What it allows | Concept it teaches |
|---|---|---|
| `allow-scraping` | ingress to flux-system pods on the metrics port | how Prometheus is permitted to scrape across namespaces |
| `allow-webhooks` | ingress to flux-system (e.g. notification webhooks) | allowing a specific inbound path |
| `allow-egress` | all egress from flux-system | egress vs ingress policy types |

Inspect them on the running cluster:

```bash
kubectl get networkpolicy -n flux-system
kubectl describe networkpolicy allow-scraping -n flux-system
```

### How a NetworkPolicy is read

- It selects pods with `spec.podSelector` (`{}` = all pods in the namespace).
- Once *any* Ingress policy selects a pod, that pod **denies all ingress except**
  what some policy explicitly allows (policies are additive / OR'd).
- `from`/`to` peers are chosen with `podSelector` (same namespace),
  `namespaceSelector` (other namespaces; every namespace has the auto-applied
  `kubernetes.io/metadata.name=<name>` label), or `ipBlock` (CIDRs).

### If you ever want to add one for an app

It's a one-file change, co-located with the app (community best-practice, even
though prod doesn't do it):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-traefik
  namespace: <app-namespace>
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: traefik
```

Add it to the app's `kustomization.yaml` `resources`. No Calico CRDs or `dependsOn`
needed — it's a core `networking.k8s.io/v1` object that Calico enforces.

---

## Verification (after `cd terraform && make destroy && make dev-services`)

```bash
# 1. Calico is the CNI and healthy
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system          # calico-node, typha, kube-controllers Running
kubectl get pods -n calico-apiserver       # calico-apiserver Running
kubectl get nodes                          # all Ready (proves CNI programmed pod networking)
kubectl get installation default -o jsonpath='{.spec.cni.type}{"\n"}'   # Calico

# 2. Flux reconciled on top of Calico
kubectl get kustomizations -A              # all READY=True

# 3. Flux's network policies exist and are now enforced
kubectl get networkpolicy -n flux-system   # allow-egress, allow-scraping, allow-webhooks
```

If `monitoring`/other pods come up healthy and the Traefik UIs still resolve, the
CNI swap is transparent to the rest of the stack — which is the goal.

---

## References

- [Calico tigera-operator Helm chart](https://docs.tigera.io/calico/charts)
- [Calico on KinD](https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Flux network policies (gotk-components)](https://fluxcd.io/flux/security/#network-policy)
