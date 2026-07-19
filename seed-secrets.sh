#!/usr/bin/env bash
# Re-seed secrets into LocalStack after a restart — it doesn't persist like real Secrets Manager.
set -euo pipefail
cd "$(dirname "$0")"

source ./.env
: "${OPENCODE_ZEN_KEY:?set OPENCODE_ZEN_KEY in .env (get one at https://opencode.ai/zen)}"

pod=$(kubectl get pod -n localstack -l app.kubernetes.io/name=localstack \
  -o jsonpath='{.items[0].metadata.name}')
sm() { kubectl exec -n localstack "$pod" -- awslocal secretsmanager "$@" --region us-east-1 >/dev/null; }

# Upsert, so re-runs just refresh the value.
if sm describe-secret --secret-id opencode-zen-key 2>/dev/null; then
  sm put-secret-value --secret-id opencode-zen-key --secret-string "$OPENCODE_ZEN_KEY"
else
  sm create-secret --name opencode-zen-key --secret-string "$OPENCODE_ZEN_KEY"
fi

echo "✓ seeded opencode-zen-key — ESO will sync it into sandbox namespaces"
