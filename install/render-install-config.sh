#!/usr/bin/env bash
# Render install-config.yaml from the Terraform outputs and local secrets, then (optionally)
# run openshift-install.
#
#   install/render-install-config.sh                 # render only -> install/<cluster>/install-config.yaml
#   install/render-install-config.sh --create        # render and create the cluster
#   install/render-install-config.sh --destroy       # destroy the cluster created from install/<cluster>
#
# Inputs:
#   PULL_SECRET_FILE   path to the Red Hat pull secret JSON (console.redhat.com)      [required for --create]
#   SSH_PUBLIC_KEY_FILE path to the SSH public key injected on the nodes              [default ~/.ssh/id_ed25519.pub]
#   GOOGLE_CREDENTIALS / ~/.gcp/osServiceAccount.json  installer service-account key   [required for --create]
#   WORKER_REPLICAS, WORKER_TYPE, CONTROL_PLANE_TYPE, PUBLISH                         [optional overrides]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
ACTION="${1:-render}"

for tool in terraform jq envsubst; do
  command -v "$tool" >/dev/null || { echo "missing tool: ${tool}" >&2; exit 2; }
done

echo "==> reading terraform outputs"
OUT="$(terraform -chdir="$TF_DIR" output -json install_config)"
export CLUSTER_NAME="$(jq -r .cluster_name <<<"$OUT")"
export BASE_DOMAIN="$(jq -r .base_domain <<<"$OUT")"
export PROJECT_ID="$(jq -r .project_id <<<"$OUT")"
export REGION="$(jq -r .region <<<"$OUT")"
export NETWORK="$(jq -r .network <<<"$OUT")"
export CONTROL_PLANE_SUBNET="$(jq -r .control_plane_subnet <<<"$OUT")"
export COMPUTE_SUBNET="$(jq -r .compute_subnet <<<"$OUT")"
export MACHINE_CIDR="$(jq -r .machine_cidr <<<"$OUT")"

export WORKER_REPLICAS="${WORKER_REPLICAS:-3}"
export WORKER_TYPE="${WORKER_TYPE:-n2-standard-4}"
export CONTROL_PLANE_TYPE="${CONTROL_PLANE_TYPE:-n2-standard-4}"
export PUBLISH="${PUBLISH:-External}"

SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
export SSH_PUBLIC_KEY="$(cat "$SSH_PUBLIC_KEY_FILE")"
if [[ -n "${PULL_SECRET_FILE:-}" ]]; then
  export PULL_SECRET="$(jq -c . "$PULL_SECRET_FILE")"
else
  export PULL_SECRET='{"auths":{}}'
  echo "warning: PULL_SECRET_FILE not set, rendering with an empty pull secret (render only)" >&2
fi

DIR="${ROOT}/install/${CLUSTER_NAME}"
mkdir -p "$DIR"
envsubst < "${ROOT}/install/install-config.yaml.tpl" > "${DIR}/install-config.yaml"
# openshift-install consumes (deletes) install-config.yaml; keep a copy for audit and re-runs.
cp "${DIR}/install-config.yaml" "${DIR}/install-config.yaml.bak"
chmod 600 "${DIR}/install-config.yaml" "${DIR}/install-config.yaml.bak"
echo "==> rendered ${DIR}/install-config.yaml (cluster ${CLUSTER_NAME}.${BASE_DOMAIN} in ${PROJECT_ID}/${REGION})"

case "$ACTION" in
  render) ;;
  --create)
    command -v openshift-install >/dev/null || { echo "openshift-install not found" >&2; exit 2; }
    [[ -n "${PULL_SECRET_FILE:-}" ]] || { echo "PULL_SECRET_FILE is required to create a cluster" >&2; exit 2; }
    echo "==> openshift-install create cluster (this takes about 40 minutes)"
    openshift-install create cluster --dir "$DIR" --log-level info
    echo "==> kubeconfig: ${DIR}/auth/kubeconfig"
    ;;
  --destroy)
    openshift-install destroy cluster --dir "$DIR" --log-level info
    ;;
  *)
    echo "unknown action: ${ACTION}" >&2; exit 2 ;;
esac
