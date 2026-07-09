# CloudNativePG — Postgres as an operator

Installs the [CloudNativePG](https://cloudnative-pg.io) operator: a controller that turns a `Cluster`
custom resource into a managed PostgreSQL instance (failover, backups, connection services, and
**auto-generated credentials** — all declarative). It's the operator pattern applied to stateful data.

Added now as the database layer for **Temporal** (next), but it stands on its own as a platform
competency: managing stateful workloads via a CRD instead of a hand-rolled StatefulSet + Secret.

---

## What's here (this app)

Just the **operator** — chart `cloudnative-pg` 0.29.0 (appVersion 1.30.0), one Flux app in
`apps/base/cloudnative-pg`, installed into `cnpg-system`. It watches for `Cluster` resources but
creates no database itself.

The actual Postgres `Cluster` (the database Temporal uses) will live in the **Temporal app**, next to
its consumer — the operator here is generic infrastructure.

## Why it matters for the secrets story

When you declare a `Cluster`, CNPG **generates the app user's password itself** and writes it to a
`<cluster>-app` Secret in-cluster. Temporal reads the password from there. So the database credential
is **never seeded, never in Git, never fake** — the operator mints it at runtime. (Contrast the
LocalStack-seeded dummy creds used elsewhere for demoing ESO.)

## Verification (after reconcile)

```bash
kubectl get pods -n cnpg-system                    # cloudnative-pg controller Running
kubectl get crd clusters.postgresql.cnpg.io        # the Cluster CRD is installed
flux get kustomizations cloudnative-pg             # Ready
```

## Next
- The Temporal app declares a `Cluster` (Postgres) with two databases (`temporal`,
  `temporal_visibility`), points Temporal at the `-rw` service, and reads the CNPG-generated password.

## References
- [CloudNativePG docs](https://cloudnative-pg.io/docs/) · [Helm chart](https://github.com/cloudnative-pg/charts)
