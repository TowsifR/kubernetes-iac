# Temporal — durable orchestration

Temporal is a workflow engine for **durable execution**: long-running, stateful processes that survive
crashes and restarts, with automatic retries and full history. It's the orchestration plane for the
sandbox platform — the intended home for sandbox lifecycle workflows (provision → ready → TTL cleanup),
where a `ttl` field on the `Sandbox` API finally earns its keep.

This ships Temporal itself; wiring it *into* the Sandbox lifecycle is the follow-on.

---

## The app — three pieces in one folder

| File | What |
|---|---|
| `postgres-cluster.yaml` | a CloudNativePG `Cluster` — the Postgres backing Temporal |
| `helmrelease.yaml` | Temporal (chart `1.5.0` / appVersion `1.31.1`), all bundled backends off |
| `ingressroute.yaml` | Traefik route to the Web UI at `temporal.localtest.me` |

Flux: `dependsOn [cloudnative-pg, traefik]` — the CNPG operator must exist to reconcile the `Cluster`,
and Traefik provides the `IngressRoute` CRD.

## Persistence — one Postgres, two databases

Temporal needs a **default** store (workflow state) and a **visibility** store (list/query workflows).
The chart bundles Cassandra + Elasticsearch by default; we disable all of it and use a single
CloudNativePG-managed Postgres holding both databases:

- `Cluster` bootstrap `initdb` creates `temporal` (the default store).
- `postInitSQL` (run as superuser) creates the second database, `temporal_visibility`.
- Temporal connects to the CNPG read-write service **`temporal-postgresql-rw`**, reading the password
  from the CNPG-generated `temporal-postgresql-app` Secret (`existingSecret` + `secretKey: password`) —
  **no credential in Git**.

## Decisions & gotchas baked in (verified via `helm template` against 1.5.0)

- **`createDatabase: false` *per datastore*.** In 1.x, schema control is per-store, not global — the old
  `schema.setup`/`update`/`createDatabase` keys were removed and now hard-`fail` the render. Default is
  `true` (tries `CREATE DATABASE`), but CNPG already made both DBs and the app user has no `CREATEDB`
  grant, so it's `false`; `manageSchema: true` still builds the tables.
- **Two databases, not one shared.** Pointing both the default and visibility stores at a *single*
  database can leave the visibility schema (`executions_visibility`) unbuilt — the store then fails
  **silently**: visibility tasks are dead-lettered while the server keeps reporting `Running`. A separate
  `temporal_visibility` DB (via `postInitSQL`) + `manageSchema: true` guarantees its tables get created.
  This failure is invisible in `kubectl get pods`, so verify the schema explicitly (below).
- **No bundled datastores.** 1.x dropped the bundled Cassandra/Elasticsearch/monitoring subcharts
  entirely — you bring your own DB. Nothing to "disable"; we just point at CNPG.
- **`schema.useHelmHooks: false`.** The chart gates schema setup on Helm hooks by default; under Flux
  that doesn't fit, so the schema job runs as a plain Job.
- **`shims.{dockerize,elasticsearchTool}: false`.** The server image is 1.31.x; those shims exist only
  for ≤1.29 image compatibility and must be off for ≥1.30.
- **Chart 1.x, not fleet-infra's 0.62.x.** A major bump restructured persistence and schema — copying
  the older config verbatim fails to render. Every value here was confirmed with `helm template`.
- **First-run ordering.** Temporal's schema job can start before CNPG finishes provisioning Postgres; it
  retries and `install.remediation.retries` re-runs the release — expect a transient CrashLoop that
  self-heals once the DB is up (hence the 15m Kustomization timeout).

## Verification (after reconcile)

```bash
kubectl get cluster -n temporal temporal-postgresql        # STATUS: Cluster in healthy state
kubectl get secret -n temporal temporal-postgresql-app     # CNPG-generated creds exist
kubectl get pods -n temporal                               # postgres + temporal frontend/history/matching/worker + web Running
flux get kustomizations temporal                           # Ready

# Visibility schema actually built — the silent-failure guard (the server stays "Running" even if broken):
kubectl exec -n temporal temporal-postgresql-1 -c postgres -- \
  psql -U postgres -d temporal_visibility -tAc '\dt' | grep -q executions_visibility \
  && echo "visibility schema OK" || echo "!! visibility schema MISSING"
kubectl logs -n temporal deploy/temporal-history --tail=300 | \
  grep -i 'executions_visibility.*does not exist' && echo "!! visibility BROKEN" || echo "no visibility errors"

# UI:
open http://temporal.localtest.me
```

## Next
- **Wire Temporal into the Sandbox lifecycle** — the actual orchestration use case (provision → ready →
  TTL cleanup), where a `ttl` field on the Sandbox API finally earns its place.
- Optional: a `ServiceMonitor` so kube-prometheus-stack scrapes Temporal; basicAuth on the UI.

> The `default` Temporal namespace is auto-created via `server.config.namespaces.create`, so no manual
> `tctl`/`operator namespace create` step is needed.

## References
- [Temporal Helm chart](https://github.com/temporalio/helm-charts) ·
  [cloudnative-pg-implementation.md](cloudnative-pg-implementation.md) — the Postgres operator
