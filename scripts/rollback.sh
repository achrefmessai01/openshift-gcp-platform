#!/usr/bin/env bash
# Roll subscriber-api back to the previous (or a given) Deployment revision and re-run the
# smoke tests so the rollback itself is verified.
#
#   scripts/rollback.sh <dev|staging|prod> [revision]
set -euo pipefail

ENV_NAME="${1:?usage: rollback.sh <env> [revision]}"
REVISION="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="subscriber-api-${ENV_NAME}"

command -v oc >/dev/null || { echo "oc not found in PATH" >&2; exit 2; }

echo "==> revision history"
oc -n "$NAMESPACE" rollout history deployment/subscriber-api

if [[ -n "$REVISION" ]]; then
  oc -n "$NAMESPACE" rollout undo deployment/subscriber-api --to-revision="$REVISION"
else
  oc -n "$NAMESPACE" rollout undo deployment/subscriber-api
fi
oc -n "$NAMESPACE" annotate deployment/subscriber-api \
  kubernetes.io/change-cause="rollback by ${USER:-pipeline} $(date -u +%FT%TZ)" --overwrite

oc -n "$NAMESPACE" rollout status deployment/subscriber-api --timeout="${ROLLOUT_TIMEOUT:-180s}"

ROUTE_HOST="$(oc -n "$NAMESPACE" get route subscriber-api -o jsonpath='{.spec.host}')"
echo "==> smoke tests against https://${ROUTE_HOST}"
python3 "${ROOT}/tools/acceptance.py" --base-url "https://${ROUTE_HOST}" --env "${ENV_NAME}-rollback" \
  --api-key "${API_KEY:-}" --include smoke
