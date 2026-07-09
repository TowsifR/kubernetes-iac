# Governance — Kyverno on the Sandbox API

Policy-as-code in front of the control plane. Kyverno is an admission webhook: it inspects a `Sandbox`
claim *before* Crossplane acts and **rejects** anything that violates policy. This is the "governed" in
"governed sandbox platform" — self-service, but within guardrails.

```
kubectl apply Sandbox
   └─ Kyverno admission webhook   ← rejects here if policy fails
        └─ Crossplane Composition reconciles the bundle
```

---

## Two apps

| App | What | Flux Kustomization |
|---|---|---|
| `apps/base/kyverno` | the engine (Helm chart 3.8.1 / app v1.18.1) | `kyverno` |
| `apps/base/sandbox-policies` | the `ClusterPolicy` resources | `sandbox-policies` (dependsOn: `kyverno`, `sandbox-platform`) |

The split is deliberate: the policies can't exist until the engine's CRDs are installed *and* the
`Sandbox` CRD they match on exists — hence the `dependsOn`. (Install and policies are one flat app only
if you have no policies.)

**Install notes:** replicas dropped from the chart's HA default of 3 → 1 per controller (single-node
KinD); `crds: CreateReplace` so chart upgrades can evolve the CRDs.

## The policy — image allowlist

The one field worth governing is `image` (everything else is already constrained by the XRD schema:
`size` is an enum, `owner` is required). Nothing stops a user running an arbitrary image in the sandbox
— so:

```yaml
validate:
  failureAction: Enforce          # block, don't just audit
  deny:
    conditions:
      any:
        - key: "{{ request.object.spec.image }}"
          operator: AnyNotIn
          value: [busybox:1.36, python:3.12-slim, node:20-slim]
```

Matched against **both** `Sandbox` (the claim — gives the user the rejection message) and `XSandbox`
(the composite — closes the bypass of creating one directly).

**1.18 syntax note:** `failureAction` is **per-rule** (under `validate`). The old spec-level
`validationFailureAction` is deprecated since 1.13 — a trap if you copy policies from older repos.

**Ordering with the XRD default:** `image` defaults to `busybox:1.36` in the XRD. CRD defaulting runs
*before* validating webhooks, so a claim that omits `image` is defaulted first, then validated — and
`busybox:1.36` is on the allowlist, so it passes.

## Verification

```bash
kubectl get pods -n kyverno                        # controllers Running
kubectl get clusterpolicy sandbox-image-allowlist  # READY=true

# allowed → admitted
kubectl apply -f - <<'EOF'
apiVersion: platform.example.io/v1alpha1
kind: Sandbox
metadata: { name: ok, namespace: default }
spec: { owner: alice, image: python:3.12-slim }
EOF

# disallowed → REJECTED at apply time
kubectl apply -f - <<'EOF'
apiVersion: platform.example.io/v1alpha1
kind: Sandbox
metadata: { name: bad, namespace: default }
spec: { owner: alice, image: nginx:latest }
EOF
# Error from server: ... spec.image "nginx:latest" is not permitted. Allowed images: ...
```

That rejection is the demo money-shot: the platform said no before anything was provisioned.

## Roadmap
- Optional: an `owner`-format rule (lowercase DNS-safe, since it becomes a label).
- A registry-prefix allowlist instead of exact tags, for a more realistic policy.
- Orchestration (Temporal) for durable lifecycle — where a `ttl` field earns its place.

## References
- [Kyverno validate rules](https://kyverno.io/docs/policy-types/cluster-policy/validate/)
- [sandbox-control-plane-implementation.md](sandbox-control-plane-implementation.md) — the API being governed
