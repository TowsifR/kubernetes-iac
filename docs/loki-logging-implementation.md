# Loki Logging Stack Implementation

Adds the **logs** pillar of observability alongside the existing metrics stack.
Grafana Alloy ships pod logs to Loki, Loki stores chunks in LocalStack S3 (bucket
provisioned by Crossplane), and logs are queried in the existing Grafana.

---

## Architecture

```
Alloy (DaemonSet, tails /var/log/pods on each node)
   └── push ──► Loki (SingleBinary, :3100)
                  └── chunks ──► LocalStack S3  (bucket: loki-chunks)
                                   ▲ provisioned by a Crossplane Bucket CR
Grafana (existing) ── "Loki" datasource ──► Loki :3100
```

Everything lives in a new **`logging`** namespace (the way `monitoring` groups
Prometheus/Grafana/Alertmanager — related components together, not one namespace each).

---

## Components & why each choice

| Component | Choice | Why |
|---|---|---|
| **Loki deployment** | `SingleBinary`, 1 replica | One pod is right for a single-node dev cluster; SimpleScalable/microservices add components with no benefit here |
| **Chunk storage** | LocalStack S3 via `s3ForcePathStyle` + `insecure` + custom `endpoint` | Exercises real object-storage config against the emulator; same shape as production S3 |
| **Bucket creation** | Crossplane `Bucket` CR | Stays in GitOps; reuses the existing Crossplane → LocalStack wiring instead of a startup script |
| **Index/WAL** | `emptyDir` (`persistence.enabled: false`) | KinD has no default StorageClass; the index rebuilds from chunks, so ephemeral is fine for dev |
| **Caches** | disabled | `chunksCache`/`resultsCache` are memcached deployments — unnecessary weight locally |
| **Log agent** | Grafana **Alloy** (DaemonSet) | Current Grafana agent; Promtail is end-of-life |

---

## How the pieces connect

### Loki → LocalStack S3
The Loki chart's `loki.storage.s3` block carries the three flags that make an AWS SDK
talk to an emulator instead of real AWS:
- `endpoint: localstack.localstack.svc.cluster.local:4566`
- `s3ForcePathStyle: true` — use `endpoint/bucket/...` URLs, not `bucket.endpoint`
- `insecure: true` — plain http

### Credentials (reused via ESO)
No credentials live in the Loki config. An `ExternalSecret` (`apps/base/loki/externalsecret.yaml`)
reuses the existing `localstack-secretsmanager` ClusterSecretStore and the `crossplane-aws-credentials`
remote secret — the same source the Crossplane provider authenticates with — to sync an
`aws-credentials` Secret into the `logging` namespace. That secret is the AWS *shared credentials file*
(INI) format, so it's mounted at `/etc/aws/credentials` and `AWS_SHARED_CREDENTIALS_FILE` points Loki's
S3 client at it. With no keys in config, Loki uses the default credential chain — the same mechanism
real IRSA relies on.

To give another app the same creds, add an `ExternalSecret` referencing the same ClusterSecretStore.

### Bucket via Crossplane
`apps/base/loki/bucket.yaml` is an `s3.aws.crossplane.io/v1beta1` `Bucket` referencing the
existing `default` ProviderConfig (which points at LocalStack). Crossplane creates the
`loki-chunks` bucket in LocalStack S3 and keeps reconciling it. `locationConstraint: ""`
because us-east-1 must not send an explicit constraint.

### Alloy → Loki
Alloy mounts the node's `/var/log` and tails container log files under
`/var/log/pods/<ns>_<pod>_<uid>/<container>/*.log`. `discovery.kubernetes` provides pod
metadata, `discovery.relabel` turns it into `namespace`/`pod`/`container` labels and builds
the file path, and `loki.write` pushes to `http://loki.logging.svc.cluster.local:3100`. The
file-tailing approach avoids needing `pods/log` API permissions.

### Grafana datasource
`apps/base/loki/grafana-datasource.yaml` is a ConfigMap in the **`monitoring`** namespace
labeled `grafana_datasource: "1"`. The kube-prometheus-stack Grafana sidecar discovers it
and registers the Loki datasource automatically — no change to that HelmRelease.

---

## Flux ordering

```
loki   dependsOn  crossplane-provider-aws (Bucket CRD + provider) + localstack (S3 endpoint)
alloy  dependsOn  loki                    (push endpoint + the logging namespace)
```

`apps/base/loki` and `apps/base/alloy` are wired via
`clusters/dev/services/loki.yaml` and `alloy.yaml`.

---

## Verification (after `make dev-services`)

```bash
# 1. Bucket provisioned in LocalStack
kubectl get bucket loki-chunks                       # READY=True, SYNCED=True

# 2. Loki + Alloy healthy
kubectl get pods -n logging                          # loki Running, alloy DaemonSet Running
kubectl get kustomizations -A                        # loki, alloy READY=True

# 3. Chunks actually landing in S3 (after a few minutes)
kubectl exec -n localstack deploy/localstack -- \
  awslocal s3 ls s3://loki-chunks --recursive | head

# 4. Logs visible in Grafana
#    http://grafana.localtest.me → Explore → "Loki" datasource → {namespace="logging"}
```

---

## Adding logs for a new app

Nothing to do — Alloy collects logs from **all** pods on every node automatically. New
workloads show up in Loki under their `namespace`/`pod`/`container` labels with no config.

---

## References

- [Loki Helm chart](https://github.com/grafana/loki/tree/main/production/helm/loki)
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Alloy: collect Kubernetes logs](https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/)
- [Loki storage config](https://grafana.com/docs/loki/latest/configure/storage/)
