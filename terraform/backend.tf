# Remote state in a versioned GCS bucket created once by scripts/bootstrap-state.sh.
# The bucket name is passed at init time so the same code serves several projects:
#   terraform init -backend-config="bucket=<project>-tfstate" -backend-config="prefix=openshift/<name>"
terraform {
  backend "gcs" {}
}
