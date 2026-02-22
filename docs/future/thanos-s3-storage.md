# Future: Thanos + S3 Long-Term Prometheus Storage

Deferred implementation plan for adding persistent long-term metric storage to the monitoring stack via Thanos sidecar and LocalStack S3.

---

## The Problem

By default, `kube-prometheus-stack` configures Prometheus with `emptyDir` storage — metrics live in the pod's ephemeral filesystem. When the pod restarts (node reboot, OOM kill, upgrade), **all metrics are lost**. For a learning project this is acceptable short-term, but it limits the usefulness of the monitoring stack.

A Persistent Volume Claim (PVC) would survive pod restarts, but KinD has no default StorageClass. You'd need to install a local provisioner (e.g. `local-path-provisioner`) to get PVCs working.

The more production-aligned solution — and the one fleet-infra uses — is Thanos.

---

## How Thanos Sidecar Solves It

Thanos is a set of components that extend Prometheus for high availability and long-term storage. The minimal piece needed here is the **Thanos sidecar**:

```
Prometheus pod
├── prometheus container    ←─ scrapes metrics, short local retention (1d)
└── thanos-sidecar container ←─ uploads completed 2h blocks to S3
                                 exposes gRPC endpoint for Thanos Query
```

Every 2 hours, Prometheus finalizes a "block" (a chunk of its TSDB). The Thanos sidecar detects the new block and uploads it to S3 in the background. Prometheus only needs to retain ~1 day locally (enough to overlap with in-progress blocks). Everything older lives in S3.

**Result:** Metrics survive indefinitely in S3, independent of the Prometheus pod lifecycle.

---

## Why This Fits This Project

- **LocalStack already has S3 enabled** (`startServices` includes `s3`) — no extra infrastructure needed
- **Same pattern as fleet-infra** — they use real S3 with Thanos sidecar; we just swap the endpoint for LocalStack
- **Natural tie-in** to the Terraform/Crossplane resource provisioning question — the S3 bucket that Thanos needs is the exact bucket that Terraform or Crossplane would provision

---

## What's Needed to Implement

### 1. Create the S3 Bucket in LocalStack

The simplest option: add bucket creation to the LocalStack startup script in `kubernetes/apps/base/localstack/helmrelease.yaml`:

```bash
startupScriptContent: |
  #!/bin/bash
  # Existing: creates crossplane credentials secret
  awslocal secretsmanager create-secret \
    --name crossplane-aws-credentials \
    --region us-east-1 \
    --secret-string "[default]
  aws_access_key_id = test
  aws_secret_access_key = test"

  # New: create the Thanos metrics bucket
  awslocal s3 mb s3://thanos-data --region us-east-1
```

**Alternative approaches** (more involved, but more educational):
- **Terraform**: Add `aws_s3_bucket "thanos_data"` in a new `terraform/localstack-resources/` module (requires port-forwarding LocalStack first)
- **Crossplane**: Add an `s3.aws.crossplane.io/v1beta1/Bucket` managed resource to the Crossplane apps

All three produce the same result from Thanos's perspective — a bucket named `thanos-data` accessible at the LocalStack endpoint.

### 2. Create the Thanos Object Store Secret

Thanos needs an `objstore.yml` config telling it where the bucket is. Create a new file:

**`kubernetes/apps/base/kube-prometheus-stack/thanos-objstore-secret.yaml`**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-objstore-config
  namespace: monitoring
type: Opaque
stringData:
  objstore.yml: |
    type: S3
    config:
      bucket: thanos-data
      endpoint: localstack.localstack.svc.cluster.local:4566
      region: us-east-1
      access_key: test
      secret_key: test
      insecure: true            # HTTP, not HTTPS
      signature_version2: false
```

Add this file to `kubernetes/apps/base/kube-prometheus-stack/kustomization.yaml`:
```yaml
resources:
  - namespace.yaml
  - helmrepository.yaml
  - helmrelease.yaml
  - thanos-objstore-secret.yaml   # ADD
```

### 3. Enable Thanos Sidecar in HelmRelease

Add to the `prometheus` section in `kubernetes/apps/base/kube-prometheus-stack/helmrelease.yaml`:

```yaml
prometheus:
  prometheusSpec:
    # ... existing values (serviceMonitorSelectorNilUsesHelmValues: false, retention: 1d, etc.) ...
    thanos:
      image: quay.io/thanos/thanos:v0.37.2
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore-config
          key: objstore.yml
  thanosService:
    enabled: true    # Exposes gRPC port for Thanos Query (useful for future Query component)
```

The `thanos.image` version should match what fleet-infra uses — check `base/environment.env` in fleet-infra for the current version.

---

## Verification

```bash
# 1. Check LocalStack created the bucket
kubectl exec -n localstack deployment/localstack -- awslocal s3 ls

# 2. Check prometheus pod has 2/2 containers (prometheus + thanos-sidecar)
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# 3. Check sidecar logs for upload activity
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -c thanos-sidecar

# 4. After ~2 hours, check blocks uploaded to S3
kubectl exec -n localstack deployment/localstack -- \
  awslocal s3 ls s3://thanos-data --recursive
```

---

## Future Extensions

Once the sidecar is in place, the next natural additions are:

### Thanos Query

A query frontend that can read data from both the live Prometheus instance (recent data) and S3 (historical data), presenting them as a unified view:

```yaml
# Would be added to kube-prometheus-stack values
thanosRuler:
  enabled: false  # Not needed yet
```

Or deployed as a separate Helm chart (`bitnami/thanos`). In fleet-infra, Grafana's `additionalDataSources` points to Thanos Query instead of Prometheus directly, allowing it to show data older than Prometheus's local retention.

### Thanos Compactor

Downloads old blocks from S3, compacts and downsamples them (5m and 1h resolution), then re-uploads. Reduces storage space and speeds up queries over long time ranges. Runs as a separate deployment. Fleet-infra deploys this as part of the Thanos Helm chart.

### Connection to fleet-infra Pattern

```yaml
# fleet-infra helmrelease.yaml (production)
prometheus:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/...  # IRSA
  prometheusSpec:
    thanos:
      image: quay.io/thanos/thanos:v0.39.2
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore-config  # Contains real S3 bucket config
          key: objstore.yml

# This project (local equivalent)
prometheus:
  prometheusSpec:
    thanos:
      image: quay.io/thanos/thanos:v0.37.2
      objectStorageConfig:
        existingSecret:
          name: thanos-objstore-config  # Contains LocalStack S3 config
          key: objstore.yml
```

The only difference is the S3 endpoint URL and the absence of IRSA — the structural pattern is identical.

---

## Related Docs

- `docs/kube-prometheus-stack-implementation.md` — base monitoring stack setup
- `docs/localstack-eso-setup.md` — LocalStack service configuration
- `docs/future/infrastructure-layer.md` — other deferred infrastructure improvements
