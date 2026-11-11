#!/usr/bin/env bash
# One-time creation of the Terraform state bucket (versioned, private, uniform access).
#
#   scripts/bootstrap-state.sh <project-id> [bucket-name] [location]
set -euo pipefail

PROJECT_ID="${1:?usage: bootstrap-state.sh <project-id> [bucket-name] [location]}"
BUCKET="${2:-${PROJECT_ID}-tfstate}"
LOCATION="${3:-EU}"

if gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "bucket gs://${BUCKET} already exists"
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "$PROJECT_ID" --location "$LOCATION" \
    --uniform-bucket-level-access --public-access-prevention
  echo "created gs://${BUCKET}"
fi
gcloud storage buckets update "gs://${BUCKET}" --versioning

cat <<EOF

Initialise Terraform with:
  terraform -chdir=terraform init \\
    -backend-config="bucket=${BUCKET}" \\
    -backend-config="prefix=openshift/\${CLUSTER_NAME:-ocp}"
EOF
