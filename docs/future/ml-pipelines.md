# Future: Batch Orchestration + ML Pipelines (Argo Workflows + MLflow)

## Why This Is Deferred

A separate track from the [AI-agents direction](./ai-agents-on-kubernetes.md). This one is
**MLOps / data-engineering** shaped (reproducible pipelines, scheduled jobs, model registry)
rather than agentic-AI shaped. Both are good portfolio stories; they just point at different
job descriptions. Captured here so the idea isn't lost — build whenever.

The nice property: **both components are useful with an empty start**, so there's no
chicken-and-egg blocker. Install them via Flux like any other app, then grow into them.

## The Two Components

### Argo Workflows — general batch/DAG engine (NOT just ML)
Kubernetes-native engine for **finite, run-to-completion** work — each step is a pod.
Orthogonal to Flux: Flux holds the cluster at steady state, Argo Workflows runs jobs.
Install it *via* Flux like any other app. Useful even with zero ML:
- Scheduled jobs via **CronWorkflow** (Argo's built-in cron) — backups, report generation,
  LocalStack housekeeping, periodic data fetches.
- Event-driven runs via **Argo Events** (e.g. file lands in LocalStack S3 → workflow fires) —
  this is the same trigger mechanism as the event-driven AI-pipeline idea in the agents doc.
- A visible **Workflows UI** (expose at `argo-workflows.localtest.me` via Traefik) — good for demos.

> Reframe: think of Argo Workflows as the project's missing **batch layer**. The current
> stack is all long-running services; there is no orchestration/cron capability yet.

### MLflow — the piece that makes it "MLOps"
Turns "a script that trains a model" into a story: **experiment tracking** (params/metrics/
artifacts per run), a **model registry** (versioned models, Staging → Production), and an
**artifact store** backed by the existing **LocalStack S3**. Stand it up empty; runs appear
the first time any training script logs to it.

## Guiding Principle

**The model doesn't matter — the machinery does.** No one is impressed by accuracy; they're
impressed by reproducible pipelines, lineage, a registry, and scheduled retraining. So:
- Use **classical ML** (scikit-learn / XGBoost) on **tabular** data → trains in seconds on
  CPU. **No GPU needed** (important — none available in KinD/WSL2). No deep learning.
- Pick a **fun, clean dataset** so it actually gets finished. Candidate: **NBA / basketball
  stats** (clean, tabular, plentiful) — e.g. predict game outcome from box scores, or cluster
  player archetypes. Other boring-but-canonical options: UCI Adult, Titanic, California Housing.

## Pipeline Shapes (pick the shape, swap any dataset/model in)

1. **Train → evaluate → register** *(start here)*
   ```
   Argo Workflow DAG:
     ingest    → pull dataset from LocalStack S3
     preprocess→ clean/split, write features back to S3
     train     → fit model, log params+metrics to MLflow
     evaluate  → if metric > threshold, promote in MLflow registry; else fail the run
     register  → tag model version "Production"
   ```
2. **Scheduled retraining** — same DAG as a **CronWorkflow** (e.g. nightly). Shows you know
   models go stale. Trivial once #1 exists.
3. **Event-driven retraining** — new data in LocalStack S3 → Argo Events → run #1. Bridges to
   the agents doc's event-driven idea.
4. **Batch inference** — separate workflow: pull "Production" model from MLflow registry,
   score a batch from S3, write predictions back. Shows training ≠ serving.

## Reuses the Existing Stack

| Need | Existing piece |
|---|---|
| Artifact / data store | LocalStack S3 |
| Secrets (registry creds, etc.) | ESO ← LocalStack Secrets Manager |
| Metrics | kube-prometheus-stack |
| UI ingress | Traefik (`*.localtest.me`) |
| Install / GitOps | Flux (`apps/base/` + a Flux Kustomization) |

## What I'd Build First

**Argo Workflows + MLflow installed (both empty), plus pipeline #1 on a fun dataset, then
add #2 (cron retraining).** Smallest thing that tells a complete MLOps story:

> "Reproducible ML pipelines on Kubernetes — Argo Workflows orchestrates training, MLflow
> tracks experiments and versions models, LocalStack S3 stores artifacts, retraining runs on
> a schedule."

## When Picking This Up

1. `kubernetes/apps/base/argo-workflows/` (namespace, HelmRepository, HelmRelease,
   kustomization) + `kubernetes/clusters/dev/services/argo-workflows.yaml` (Flux Kustomization).
   Expose UI via a Traefik IngressRoute.
2. `kubernetes/apps/base/mlflow/` similarly; point its artifact store at LocalStack S3 and
   wire creds via ESO (reuse the Crossplane/LocalStack creds pattern).
3. Write the first `Workflow` / `CronWorkflow` manifest for pipeline #1.
4. `docs/argo-workflows-implementation.md` documenting the DAG, MLflow integration, and S3 wiring.
