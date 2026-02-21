# LocalStack + External Secrets Operator Setup

## Overview

LocalStack runs as a Helm chart inside the cluster and emulates AWS services (S3, SQS, Secrets Manager, etc.). External Secrets Operator (ESO) reads secrets from LocalStack's Secrets Manager and creates native Kubernetes Secrets. This mirrors the production pattern in fleet-infra where ESO pulls secrets from AWS Secrets Manager.

## Architecture

```
LocalStack (startup script)
  → seeds secret in Secrets Manager

ESO (env vars: AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY/AWS_ENDPOINT_URL_SECRETS_MANAGER)
  → ClusterSecretStore defines which backend to use
    → ExternalSecret pulls secret by name
      → Kubernetes Secret created in target namespace
        → Crossplane reads the Secret
```

## Components

### 1. LocalStack (`apps/base/localstack/`)

Deployed via Flux HelmRelease from `localstack.github.io/helm-charts`.

**Key values:**
- `startServices` — pre-loads specific AWS services at startup (avoids lazy loading)
- `enableStartupScripts: true` — enables the init script mechanism
- `startupScriptContent` — runs `awslocal` commands once LocalStack is ready

**Startup script** seeds the Crossplane AWS credentials into Secrets Manager:
```bash
awslocal secretsmanager create-secret \
  --name crossplane-aws-credentials \
  --region us-east-1 \
  --secret-string "[default]
aws_access_key_id = test
aws_secret_access_key = test"
```

This runs inside the LocalStack pod via the `/etc/localstack/init/ready.d` hook — LocalStack executes it once all services are ready.

### 2. External Secrets Operator (`apps/base/external-secrets/`)

Deployed via Flux HelmRelease from `charts.external-secrets.io`.

**Why ESO needs credentials to talk to LocalStack:**
ESO's AWS provider uses the standard AWS SDK credential chain. Since LocalStack doesn't validate credentials, we inject dummy `test/test` values as pod environment variables via `extraEnvVars` in the HelmRelease — no separate Kubernetes Secret needed.

```yaml
extraEnv:
  - name: AWS_ACCESS_KEY_ID
    value: test
  - name: AWS_SECRET_ACCESS_KEY
    value: test
  - name: AWS_DEFAULT_REGION
    value: us-east-1
  - name: AWS_ENDPOINT_URL_SECRETS_MANAGER
    value: http://localstack.localstack.svc.cluster.local:4566
```

ESO 2.0.x removed the `endpoint` field from the ClusterSecretStore CRD. The recommended approach is now to use the standard AWS SDK environment variable `AWS_ENDPOINT_URL_SECRETS_MANAGER`, which redirects all Secrets Manager calls to LocalStack at the pod level.

**In production (fleet-infra):** ESO uses IRSA — the pod's ServiceAccount token is automatically exchanged for real AWS credentials. No credentials or endpoint overrides stored anywhere.

### 3. ClusterSecretStore (`apps/base/crossplane/provider-aws/secretstore.yaml`)

A cluster-scoped ESO resource that defines how to connect to the secret backend. Because it's cluster-scoped, any namespace can reference it without needing its own SecretStore.

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: localstack-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
```

- **ClusterSecretStore** — cluster-scoped, referenceable from any namespace. Any app in the cluster can pull secrets from LocalStack without needing its own SecretStore.
- **No `auth` field** — ESO falls back to env var credentials set in the HelmRelease
- **No `endpoint` field** — ESO 2.0.x removed this field. The LocalStack endpoint is configured via `AWS_ENDPOINT_URL_SECRETS_MANAGER` on the ESO pod instead.

**In production (fleet-infra):** Also uses `ClusterSecretStore` (`cluster-secretstore-services`), IRSA auth, no endpoint override needed.

### 4. ExternalSecret (`apps/base/crossplane/provider-aws/externalsecret.yaml`)

Tells ESO which secret to pull and what Kubernetes Secret to create.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: aws-credentials
  namespace: crossplane-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: localstack-secretsmanager
    kind: ClusterSecretStore
  target:
    name: aws-credentials
    creationPolicy: Owner
  data:
    - secretKey: credentials
      remoteRef:
        key: crossplane-aws-credentials
```

- **`refreshInterval: 1h`** — ESO re-syncs the secret every hour
- **`creationPolicy: Owner`** — ESO owns the created Secret (deletes it if ExternalSecret is deleted)
- **`remoteRef.key`** — name of the secret in LocalStack Secrets Manager (set by startup script)
- **`target.name`** — name of the Kubernetes Secret ESO will create

The resulting Kubernetes Secret `aws-credentials` in `crossplane-system` is what Crossplane's ProviderConfig references.

## Deployment Order

These components have strict ordering requirements enforced via Flux Kustomization `dependsOn`:

```
apps/base (LocalStack HelmRelease)     ← deployed by root Kustomization
external-secrets                        ← no dependsOn (independent)
crossplane-base                         ← no dependsOn (independent)
crossplane-config                       ← dependsOn: crossplane-base
crossplane-provider-aws                 ← dependsOn: crossplane-config + external-secrets
```

`crossplane-provider-aws` waits for both `crossplane-config` (so ProviderConfig CRD exists) and `external-secrets` (so SecretStore/ExternalSecret CRDs exist and the `aws-credentials` Secret has been created).

## Why Not Just Hardcode test/test in a Secret?

We could, and in practice the values are identical. The value here is learning the pattern:

| Approach | What you learn |
|---|---|
| Static Secret | Nothing — just YAML |
| LocalStack startup script + ESO | Secret seeding, SecretStore, ExternalSecret, credential chain |

In production, swapping LocalStack for real AWS would mean:
1. Remove `extraEnvVars` from ESO HelmRelease (use IRSA instead)
2. Remove `AWS_ENDPOINT_URL_SECRETS_MANAGER` env var from ESO HelmRelease
3. The ClusterSecretStore, ExternalSecret, and ProviderConfig stay the same

## Verification

```bash
# ESO running
kubectl get pods -n external-secrets

# ClusterSecretStore is ready
kubectl get clustersecretstore

# ExternalSecret is synced
kubectl get externalsecret -n crossplane-system

# Kubernetes Secret was created by ESO
kubectl get secret aws-credentials -n crossplane-system

# Crossplane ProviderConfig is healthy
kubectl get providerconfig default
```
