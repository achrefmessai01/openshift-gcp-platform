# Optional bastion: private VM in the compute subnet, reachable only through IAP TCP
# forwarding (flow FW-008). Used for troubleshooting from inside the VPC (oc, dig, curl,
# tcpdump) when the API is not reachable from the admin network.

resource "google_service_account" "bastion" {
  count = var.create_bastion ? 1 : 0

  project      = var.project_id
  account_id   = "${var.name}-bastion"
  display_name = "Bastion host for ${var.name}"
}

resource "google_project_iam_member" "bastion_logging" {
  count = var.create_bastion ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion[0].email}"
}

resource "google_compute_instance" "bastion" {
  count = var.create_bastion ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-bastion"
  zone         = var.zone
  machine_type = var.bastion_machine_type
  labels       = merge(var.labels, { role = "bastion" })

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = module.network.compute_subnet_self_link
    # No access_config block: no public IP. Outbound traffic goes through Cloud NAT.
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOT
      #!/bin/bash
      set -euo pipefail
      apt-get update -y
      apt-get install -y dnsutils curl jq tcpdump mtr-tiny openssl
    EOT
  }

  service_account {
    email  = google_service_account.bastion[0].email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}
