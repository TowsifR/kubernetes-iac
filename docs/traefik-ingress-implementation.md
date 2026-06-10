# Traefik Ingress Controller Implementation

Ingress routing for the cluster via Traefik, enabling browser access to monitoring UIs (Grafana, Prometheus, Alertmanager) using hostname-based routing.

---

## What is Traefik?

Traefik is a cloud-native reverse proxy and ingress controller. It watches Kubernetes resources and automatically configures routing rules. The key difference from standard nginx-ingress is that Traefik uses its own CRDs (`IngressRoute`, `Middleware`, `TLSStore`) instead of the standard `networking.k8s.io/v1/Ingress` resource. These CRDs are more expressive — they support gRPC (`h2c` scheme), middleware chaining (auth, redirects, rate limiting), and per-route TLS configuration.

`fleet-infra` uses Traefik exclusively, so learning it here gives direct transferable knowledge to the production setup.

> **Version note:** `fleet-infra` pins the Traefik Helm chart at `25.0.0` (Traefik **v2.10**, which is past end-of-life and still uses the legacy `traefik.containo.us` CRD group). This project deliberately mirrors fleet-infra's *patterns and architecture* — Traefik as the ingress controller, `IngressRoute` CRDs, per-app route manifests, `dependsOn` ordering — but on a **current, supported chart** (`40.x` → Traefik **v3**). The one practical consequence is the CRD API group: v3 renamed `traefik.containo.us/v1alpha1` → `traefik.io/v1alpha1`. The resource structure is otherwise unchanged.

---

## Fleet-infra vs This Project

| Aspect | fleet-infra (EKS) | This project (KinD) |
|---|---|---|
| **Ingress controller** | Traefik v2.10 (chart `25.0.0`) | Traefik v3 (chart `40.x`) — same tool, current version |
| **Service type** | `LoadBalancer` → AWS Internal NLB | `NodePort` → KinD port mapping |
| **DNS** | ExternalDNS → Route53 wildcard A record | `localtest.me` public DNS (no setup needed) |
| **TLS** | Wildcard cert from Secrets Manager via ESO, set as global `tlsStore.default` | None (HTTP only) |
| **Replicas** | 2 (HA, spread across infra nodes) | 1 |
| **Node placement** | Pinned to `role=infra` nodes via affinity/tolerations | None (single-node dev) |
| **IngressRoute CRD API** | `traefik.containo.us/v1alpha1` (v2 group) | `traefik.io/v1alpha1` (v3 group) |
| **Route pattern** | `Host(grafana-sandbox.services-amer.p123.aws-us-east-1.sanofi.com)` | `Host(grafana.localtest.me)` |

The IngressRoute `spec` structure is **identical** — only the `apiVersion` group (v2→v3 rename) and the hostname differ.

---

## How it Works in KinD

The KinD cluster's Terraform module already maps host ports to node ports:

```
terraform/modules/kind-cluster/main.tf:
  extra_port_mappings:
    container_port: 30080  →  host_port: 80   (HTTP)
    container_port: 30443  →  host_port: 443  (HTTPS)
```

Traefik is deployed with a NodePort service using those same node ports. `localtest.me` is a public wildcard DNS service — any `*.localtest.me` hostname resolves to `127.0.0.1` via public DNS, so no local configuration is needed:

```
Browser: http://grafana.localtest.me
  │
  ├─ DNS: grafana.localtest.me → 127.0.0.1  (public DNS, no hosts file needed)
  │
  ├─ Docker routes host:80 → KinD control-plane container:30080
  │
  ├─ Kubernetes NodePort service routes :30080 → Traefik pod
  │
  ├─ Traefik evaluates IngressRoute rules
  │    match: Host(`grafana.localtest.me`)
  │
  └─ Forwards to: kube-prometheus-stack-grafana:80 (in monitoring namespace)
```

No LoadBalancer, no DNS provider setup, no TLS certificate, no hosts file edits.

---

## File Structure

```
kubernetes/
├── apps/base/traefik/
│   ├── namespace.yaml          # traefik namespace
│   ├── helmrepository.yaml     # https://helm.traefik.io/traefik
│   ├── helmrelease.yaml        # chart 40.x (Traefik v3), NodePort, no TLS
│   └── kustomization.yaml
├── apps/base/kube-prometheus-stack/
│   ├── ...                     # (existing)
│   └── ingressroute.yaml       # Grafana, Prometheus, Alertmanager routes
└── clusters/dev/services/
    ├── traefik.yaml             # Flux Kustomization CRD
    └── kube-prometheus-stack.yaml  # dependsOn: traefik
```

---

## Accessing the UIs

No setup required — open directly in your Windows browser:

```
http://grafana.localtest.me        → Grafana     (admin / admin)
http://prometheus.localtest.me     → Prometheus UI
http://alertmanager.localtest.me   → Alertmanager UI
```

**Note:** `localtest.me` requires internet connectivity for the DNS lookup. All actual traffic goes to `127.0.0.1` — nothing leaves your machine except the DNS query.

---

## Dependency Ordering

Traefik installs Custom Resource Definitions (CRDs) for `IngressRoute`, `Middleware`, etc. when it is first deployed. If `kube-prometheus-stack` tries to apply `ingressroute.yaml` **before** Traefik's CRDs exist, the apply will fail with "no matches for kind IngressRoute".

The `dependsOn` field on the `kube-prometheus-stack` Flux Kustomization CRD prevents this:

```yaml
# kubernetes/clusters/dev/services/kube-prometheus-stack.yaml
spec:
  dependsOn:
    - name: traefik   # Flux waits for Traefik to be READY before reconciling this
```

Flux's `wait: true` + `healthChecks` on the Traefik Kustomization ensures Traefik's HelmRelease (and its CRDs) are fully installed before `kube-prometheus-stack` proceeds.

Updated full dependency chain:
```
localstack               ──► (no deps)
external-secrets         ──► (no deps)
traefik                  ──► (no deps)
crossplane-base          ──► (no deps)
crossplane-config        ──► crossplane-base
crossplane-provider-aws  ──► crossplane-config + external-secrets
kube-prometheus-stack    ──► traefik
```

---

## Adding an IngressRoute for a New App

Any app that exposes an HTTP service can get an IngressRoute. The pattern is:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: my-app-namespace   # same namespace as the target Service
spec:
  entryPoints:
    - web                        # HTTP only (local). Add "websecure" for HTTPS.
  routes:
    - match: Host(`my-app.localtest.me`)
      kind: Rule
      services:
        - name: my-app-service   # Kubernetes Service name
          port: 8080             # Service port
```

Then:
1. Add `ingressroute.yaml` to the app's `kustomization.yaml` resources list
2. Add `dependsOn: [{name: traefik}]` to the app's Flux Kustomization CRD
3. Push to Git — Flux reconciles, open `http://my-app.localtest.me` in browser

### For apps in different namespaces

Traefik can route to services in **any** namespace — the IngressRoute does not need to be in the same namespace as Traefik itself. It just needs to be in the same namespace as the **target Service**.

---

## Verification

```bash
# 1. Check Traefik is deployed
kubectl get pods -n traefik
kubectl get svc -n traefik
# NodePort service should show: 80:30080/TCP, 443:30443/TCP

# 2. Check Flux is happy
kubectl get kustomizations -n flux-system
# Both traefik and kube-prometheus-stack should be READY=True

# 3. Check IngressRoutes are registered
kubectl get ingressroute -n monitoring
# Should show: grafana, prometheus, alertmanager

# 4. Test routing from WSL2 terminal
curl -s -o /dev/null -w "%{http_code}" http://grafana.localtest.me
# Should return 200 or 302 (Grafana login redirect)

# 5. Open in Windows browser
# http://grafana.localtest.me  (admin / admin)
```

---

## References

- [Traefik Helm chart](https://github.com/traefik/traefik-helm-chart)
- [Traefik IngressRoute docs](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- [localtest.me](https://readme.localtest.me) — public wildcard DNS for 127.0.0.1
- [fleet-infra reference: `apps/base/traefik/`](../../oneai-core-fleet-infra/apps/base/traefik/)
- [fleet-infra Grafana IngressRoute](../../oneai-core-fleet-infra/apps/base/kube-prometheus-stack/grafana-utils/grafana-ingress.yaml)
