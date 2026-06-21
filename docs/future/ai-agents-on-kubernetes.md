# Future: AI Agents on Kubernetes

## Why This Is Deferred

This is the intended next major direction for the project — an AI/Platform-Engineering
showcase that builds on the existing stack (Flux, Prometheus, ESO, LocalStack, Traefik).
It's deferred only because it's the *next* thing, not because it's blocked. The research
below was done to pick a concrete project; capture it here and revisit when ready to build.

The existing infrastructure is already the perfect substrate: Prometheus has metrics, an
agent can be exposed via Traefik at `*.localtest.me`, and the LLM API key fits the existing
**LocalStack Secrets Manager → ESO → K8s Secret** pattern (same as Crossplane credentials).

## LLM Model / Cost Notes

No GPU in KinD/WSL2, so local models (Ollama) aren't viable — a cloud LLM API is required.

| Model | Input $/1M | Output $/1M | Use for |
|---|---|---|---|
| Claude Haiku 4.5 | $1.00 | $5.00 | High-volume routing / simple classification, testing |
| Claude Sonnet 4.6 | $3.00 | $15.00 | **Recommended default** — best tool-use per dollar |
| Claude Opus 4.8 | $5.00 | $25.00 | Hardest agentic reasoning |

Agentic workloads are **input-token heavy** (every turn re-sends the full conversation +
tool results + tool definitions), so **prompt caching matters** — Claude reads cached tokens
at ~0.1× cost. Rough estimate: building the feature costs a few dollars; a 20-turn agent
loop at Sonnet pricing is ~$0.30/run.

Store the key the same way as `crossplane-aws-credentials`:
LocalStack Secrets Manager → ESO `ExternalSecret` → K8s Secret → agent pod env var.

## Candidate Projects (Research, 2026-06)

Ordered roughly easiest → most ambitious. Each is a real, active project.

### 1. k8sGPT + operator — *easiest, proven*
Scans the cluster for errors/misconfigurations and explains them in plain English. Runs as
an operator for continuous scanning. CNCF Sandbox, ~7.7k stars, plugin architecture for
custom analyzers.
- https://github.com/k8sgpt-ai/k8sgpt — https://github.com/k8sgpt-ai/k8sgpt-operator
- **Portfolio angle:** "production monitoring + AI enrichment"; extend with a custom analyzer.

### 2. Natural-language kubectl (MCP) — *showcases Claude/MCP*
Natural language → kubectl via an MCP server. Good narrative for demonstrating MCP + Claude
integration against the local KinD cluster.
- https://github.com/GoogleCloudPlatform/kubectl-ai
- https://github.com/Tarique-B-DevOps/Agentic-Kubernetes-CLI
- **Portfolio angle:** "AI-assisted platform engineering"; pairs a custom K8s MCP server with Claude.

### 3. Robusta — Prometheus → AI enrichment → remediation
Sits between Prometheus AlertManager and AI: enriches raw alerts with pod logs + relevant
graphs + AI-suggested fixes; can auto-remediate. Natural extension of the existing
kube-prometheus-stack.
- https://github.com/robusta-dev/robusta
- **Portfolio angle:** reduces alert fatigue; low-to-medium effort because it slots into existing tooling.

### 4. Kagent — *CNCF Sandbox, the "main" idea*
Framework to build/run AI agents as Kubernetes resources (`Agent`, `AgentTool`,
`ModelConfig` CRDs). Pre-built agents for Kubernetes, Prometheus, Istio, Argo. First agentic
AI framework in CNCF Sandbox (Solo.io, May 2025). Integrates with MCP servers.
- https://kagent.dev/ — https://github.com/kagent-dev/kagent
- https://www.cncf.io/blog/2025/04/15/kagent-bringing-agentic-ai-to-cloud-native/
- **Portfolio angle:** deploy Kagent + an `Agent` CR with kubectl/Prometheus/log tools,
  expose at `kagent.localtest.me`. This mirrors what fleet-infra does. Optionally add Tempo
  + OpenTelemetry traces so every LLM call and tool invocation shows up in Grafana
  ("LLM observability") — the glue that makes it feel production-grade.

### 5. Kubernaut — *most ambitious, self-healing*
LLM-driven AIOps: alert → investigate live cluster state (API + logs + Prometheus) →
pick a fix from a workflow catalog → execute or open a PR → escalate with RCA. Has approval
gates and OPA policy enforcement.
- https://github.com/jordigilh/kubernaut
- **Portfolio angle:** "intelligent self-healing system"; combine with Flux so remediations
  land as GitOps PRs. High effort.

### Emerging standard to watch
**Agent Sandbox** (`kubernetes-sigs/agent-sandbox`) — a SIG Apps subproject (KubeCon
Atlanta, Nov 2025) standardizing security/isolation for agents on Kubernetes. Several
platforms (OpenShift LiteLLM Agent Platform, etc.) already build on its CRD.
- https://github.com/kubernetes-sigs/agent-sandbox

## Leaning Toward

**Kagent (#4) as the centerpiece**, optionally with Tempo + OpenTelemetry for LLM
observability — it's the best fit for the existing stack, has a clean CRD model, mirrors the
production fleet-infra pattern, and produces a visible UI + Grafana dashboards. k8sGPT (#1)
is the low-risk fallback if a smaller scope is wanted first.

## When Picking This Up

1. Add `kubernetes/apps/base/kagent/` (namespace, HelmRepository, HelmRelease, `agent.yaml`,
   kustomization) and `kubernetes/clusters/dev/services/kagent.yaml` (Flux Kustomization,
   `dependsOn: external-secrets` for the LLM API key).
2. Store the LLM API key via LocalStack Secrets Manager → ESO (reuse the Crossplane creds pattern).
3. Optional observability: `kubernetes/apps/base/tempo/` + add a Tempo datasource to the
   kube-prometheus-stack HelmRelease values; build a Grafana dashboard for agent
   latency/token-cost/tool-call breakdown.
4. Write `docs/kagent-implementation.md` documenting the agent, its tools, and the trace pipeline.
