#!/usr/bin/env bash
# Deploy subscriber-api to an environment overlay and wait for the rollout.
#
#   scripts/deploy.sh <dev|staging|prod> [image-tag] [--acceptance]
#
# Requires an authenticated `oc` session with rights on the target namespace.
# With --acceptance, runs the smoke + functional Robot suites against the Route afterwards
# and writes the acceptance record under reports/<env>/.
set -euo pipefail

ENV_NAME="${1:?usage: deploy.sh <env> [image-tag] [--acceptance]}"
shift
IMAGE_TAG=""
RUN_ACCEPTANCE="false"
for arg in "$@"; do
  case "$arg" in
    --acceptance) RUN_ACCEPTANCE="true" ;;
    *) IMAGE_TAG="$arg" ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="${ROOT}/deploy/overlays/${ENV_NAME}"
NAMESPACE="subscriber-api-${ENV_NAME}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/achrefmessai01/subscriber-api}"
TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

[[ -d "$OVERLAY" ]] || { echo "unknown environment: ${ENV_NAME}" >&2; exit 2; }
command -v oc >/dev/null || { echo "oc not found in PATH" >&2; exit 2; }
oc whoami >/dev/null || { echo "not logged in (oc login ...)" >&2; exit 2; }

echo "==> ${ENV_NAME}: namespace ${NAMESPACE}"
if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
  oc new-project "$NAMESPACE" --display-name="subscriber-api (${ENV_NAME})" >/dev/null
fi

if ! oc -n "$NAMESPACE" get secret subscriber-api-secrets >/dev/null 2>&1; then
  if [[ -n "${API_KEY:-}" ]]; then
    oc -n "$NAMESPACE" create secret generic subscriber-api-secrets --from-literal=API_KEY="$API_KEY"
  else
    echo "warning: secret subscriber-api-secrets missing and API_KEY not set; API runs unprotected" >&2
  fi
fi

echo "==> applying ${OVERLAY}"
oc apply -k "$OVERLAY"

if [[ -n "$IMAGE_TAG" ]]; then
  echo "==> setting image ${IMAGE_REPO}:${IMAGE_TAG}"
  oc -n "$NAMESPACE" set image deployment/subscriber-api api="${IMAGE_REPO}:${IMAGE_TAG}"
  oc -n "$NAMESPACE" annotate deployment/subscriber-api \
    kubernetes.io/change-cause="deploy ${IMAGE_TAG} by ${USER:-pipeline} $(date -u +%FT%TZ)" --overwrite
fi

echo "==> waiting for rollout (timeout ${TIMEOUT})"
if ! oc -n "$NAMESPACE" rollout status deployment/subscriber-api --timeout="$TIMEOUT"; then
  echo "rollout failed; inspect with: oc -n ${NAMESPACE} get pods,events" >&2
  echo "roll back with: scripts/rollback.sh ${ENV_NAME}" >&2
  exit 1
fi

ROUTE_HOST="$(oc -n "$NAMESPACE" get route subscriber-api -o jsonpath='{.spec.host}')"
echo "==> deployed: https://${ROUTE_HOST}"

if [[ "$RUN_ACCEPTANCE" == "true" ]]; then
  echo "==> acceptance (smoke + functional) against https://${ROUTE_HOST}"
  python3 "${ROOT}/tools/acceptance.py" \
    --base-url "https://${ROUTE_HOST}" --env "$ENV_NAME" --expected-env "$ENV_NAME" \
    --api-key "${API_KEY:-}" --route-host "$ROUTE_HOST" \
    --include smoke --include functional --include platform
fi
