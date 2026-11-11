# Public managed zone for the cluster base domain. The installer creates the api and *.apps
# records in this zone; the registrar must delegate base_domain to the name servers output.

resource "google_dns_managed_zone" "base" {
  count = var.create ? 1 : 0

  project     = var.project_id
  name        = replace(var.base_domain, ".", "-")
  dns_name    = "${var.base_domain}."
  description = "OpenShift base domain ${var.base_domain}"
  visibility  = "public"
  labels      = var.labels

  dnssec_config {
    state = "on"
  }
}
