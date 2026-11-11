# APIs and identities required by the OpenShift installer-provisioned infrastructure (IPI)
# workflow on GCP. Role list follows the "Required GCP roles" section of the OpenShift
# installation documentation for GCP (installer account).

locals {
  required_services = [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "servicemanagement.googleapis.com",
    "serviceusage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
  ]

  installer_roles = [
    "roles/compute.admin",
    "roles/dns.admin",
    "roles/iam.securityAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/iam.roleViewer",
    "roles/compute.loadBalancerAdmin",
  ]
}

resource "google_project_service" "apis" {
  for_each = { for s in local.required_services : s => s if var.enable_apis }

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "installer" {
  project      = var.project_id
  account_id   = "${var.name}-installer"
  display_name = "OpenShift installer (${var.name})"
  description  = "Used by openshift-install to create and destroy the ${var.name} cluster."

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "installer" {
  for_each = toset(local.installer_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.installer.email}"
}

# Read-only identity for pipelines: terraform plan on merge requests, inventory and drift
# checks. It never gets write access to the project.
resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = "${var.name}-ci"
  display_name = "CI read-only (${var.name})"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "ci_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}
