# Object storage for the OpenShift internal image registry (configured by the ansible role
# ocp_registry: spec.storage.gcs.bucket on configs.imageregistry.operator.openshift.io).

resource "google_storage_bucket" "registry" {
  project  = var.project_id
  name     = "${var.project_id}-${var.name}-registry"
  location = upper(var.region)
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_storage_bucket_iam_member" "ci_viewer" {
  bucket = google_storage_bucket.registry.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.ci_sa_email}"
}
