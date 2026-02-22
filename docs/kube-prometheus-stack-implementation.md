# kube-prometheus-stack Implementation

Monitoring via Prometheus + Grafana, deployed with the `kube-prometheus-stack` Helm chart using Flux GitOps — mirroring the pattern from `oneai-core-fleet-infra`.

---

## What is kube-prometheus-stack?

`kube-prometheus-stack` is a Helm chart that bundles an entire monitoring stack into a single, opinionated release. It is maintained by the Prometheus community and is the de-facto standard for Kubernetes monitoring.

### Components

| Component | Purpose |
|---|---|
| **Prometheus Operator** | Watches CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`) and configures Prometheus accordingly. The "brain" of the stack. |
| **Prometheus** | Scrapes metrics from all discovered targets, stores them in its TSDB, and evaluates alerting rules. |
| **Alertmanager** | Receives firing alerts from Prometheus, deduplicates, groups, and routes them to receivers (email, Slack, PagerDuty, etc.). |
| **Grafana** | Visualisation dashboards. Pre-configured with Prometheus as a datasource. Ships with a rich set of built-in dashboards. |
| **kube-state-metrics** | Exposes metrics about Kubernetes object state (Deployment replicas, Pod phases, PVC bound status, etc.). |
| **prometheus-node-exporter** | DaemonSet that exposes host-level metrics (CPU, memory, disk, network) from each node. |

### The Operator Pattern

Rather than configuring Prometheus via a static config file, the Operator introduces Kubernetes CRDs so you configure scraping **declaratively**:

```
ServiceMonitor  ─────────────────► Prometheus scrape target
PodMonitor      ─────────────────► Prometheus scrape target
PrometheusRule  ─────────────────► Alerting / recording rule
AlertmanagerConfig ──────────────► Alertmanager routing rule
```

The Prometheus Operator watches these CRDs and automatically updates Prometheus's running configuration — no restarts needed.

---

## Architecture in this Project

### File Structure

```
kubernetes/
├── apps/base/kube-prometheus-stack/
│   ├── namespace.yaml          # monitoring namespace
│   ├── helmrepository.yaml     # prometheus-community chart repo
│   ├── helmrelease.yaml        # Helm chart + values
│   └── kustomization.yaml      # Lists all resources above
└── clusters/dev/services/
    ├── kustomization.yaml       # ← add kube-prometheus-stack.yaml here
    └── kube-prometheus-stack.yaml  # Flux Kustomization CRD
```

This follows the same pattern as `localstack`, `external-secrets`, and `crossplane-base`:
each app gets a directory under `apps/base/` with its own Flux Kustomization CRD in `clusters/dev/services/`.

### Why a Single Flux Kustomization CRD?

Some apps in this project use multiple Kustomization CRDs chained with `dependsOn` (see Crossplane's 3-stage bootstrap). Monitoring doesn't need this because:
- It installs no CRDs that other apps depend on
- There is no separate "config" stage (no AlertmanagerConfig or extra PrometheusRules in scope — yet)

If you later add `AlertmanagerConfig` resources or cluster-specific `PrometheusRule` files, you can split into `kube-prometheus-stack-base` + `kube-prometheus-stack-config` following the fleet-infra pattern.

### The `prometheus: "true"` Namespace Label

```yaml
# namespace.yaml
metadata:
  labels:
    prometheus: "true"
```

In the HelmRelease, Prometheus is configured with a `ruleNamespaceSelector` that matches this label. This tells Prometheus: **"only pick up PrometheusRule CRDs from namespaces labelled `prometheus: "true"`"**. Without this label, alerting rules you deploy into the `monitoring` namespace would be ignored.

Fleet-infra uses this same pattern — it's how you scope which namespaces Prometheus pays attention to for rules.

### `serviceMonitorSelectorNilUsesHelmValues: false`

By default, Prometheus only scrapes `ServiceMonitor` resources that have a matching label set by the Helm chart (`release: kube-prometheus-stack`). This means ServiceMonitors you create for your own apps — LocalStack, ESO, Crossplane — would be **silently ignored**.

Setting `serviceMonitorSelectorNilUsesHelmValues: false` tells Prometheus to discover **all** ServiceMonitors in the cluster regardless of labels. This is the right default for a shared monitoring stack.

### HelmRepository Namespace Convention

This project places HelmRepository objects in the same namespace as the HelmRelease (here: `monitoring`). This differs from fleet-infra which puts them in `flux-system`. Both are valid — this project's convention keeps each app's resources self-contained within its own namespace.

---

## KinD Simplifications vs fleet-infra

The production fleet-infra setup is tuned for multi-cluster EKS with enterprise requirements. Here's what's simplified and why:

| Feature | fleet-infra | This project | Reason |
|---|---|---|---|
| **Thanos sidecar** | Enabled (S3 long-term storage, multi-cluster query) | Disabled | EKS/S3-specific; not needed for local learning |
| **Persistent storage** | gp3 PVCs (Prometheus 30 Gi, Alertmanager 20 Gi) | emptyDir / no PVC | KinD has no default StorageClass |
| **etcd / kube-scheduler / kube-controller-manager** | Monitored | Disabled | These are internal to KinD nodes — not accessible from inside pods |
| **Node affinity/tolerations** | Pinned to `role=infra` nodes | Not set | KinD has no dedicated infra node pool |
| **IRSA (IAM role for Prometheus)** | Yes (Thanos needs S3 access) | N/A | No IAM in KinD |
| **Grafana SSO (Keycloak)** | Yes, via ExternalSecret | `adminPassword: admin` | No identity provider in local setup |
| **AlertmanagerConfig (email)** | Yes, SMTP routing | Not configured | No SMTP relay locally |
| **Chart version substitution** | `${KUBE_PROMETHEUS_STACK_VERSION_CHART}` from ConfigMap | Pinned in HelmRelease | No Flux variable substitution in this project |
| **Grafana additional datasources** | Loki, Tempo, Thanos Query | Prometheus only | Other tools not deployed |

---

## Accessing the Stack

After Flux reconciles (check with `kubectl get kustomizations -n flux-system`):

```bash
# Grafana UI — http://localhost:3000  (admin / admin)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus UI — http://localhost:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Alertmanager UI — http://localhost:9093
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Check all pods are running
kubectl get pods -n monitoring

# Check HelmRelease status
kubectl get helmrelease -n monitoring
```

---

## How to Add a ServiceMonitor for Your App

Once your app exposes a `/metrics` endpoint (Prometheus format), create a `ServiceMonitor` to tell Prometheus to scrape it.

### Example: scraping LocalStack

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: localstack
  namespace: localstack          # Can be in any namespace
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: localstack   # Matches the Service's labels
  endpoints:
    - port: edge                 # Name of the port in the Service
      path: /_localstack/health  # Metrics path (LocalStack-specific)
      interval: 30s
```

Because `serviceMonitorSelectorNilUsesHelmValues: false` is set, Prometheus will discover this ServiceMonitor automatically — no extra labels needed.

### Why this is powerful

In fleet-infra, every team deploys their own `ServiceMonitor` alongside their app. Prometheus picks them all up without any central configuration change. This is the Operator pattern in action: **the app declares how it should be monitored; the Operator ensures Prometheus is updated**.

---

## Dependency Chain

Monitoring is **independent** — it does not depend on LocalStack, ESO, or Crossplane, and nothing depends on it:

```
localstack          ──►  (no deps)
external-secrets    ──►  (no deps)
crossplane-base     ──►  (no deps)
crossplane-config   ──►  crossplane-base
crossplane-provider-aws  ──►  crossplane-config + external-secrets
kube-prometheus-stack    ──►  (no deps)     ← independent
```

---

## References

- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator CRD docs](https://prometheus-operator.dev/docs/user-guides/getting-started/)
- [fleet-infra reference: `apps/base/kube-prometheus-stack/`](../../../oneai-core-fleet-infra/apps/base/kube-prometheus-stack/)
