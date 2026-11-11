resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  # 1460 is the GCP default and what the OpenShift installer expects for OVN-Kubernetes.
  mtu = 1460
}

resource "google_compute_subnetwork" "control_plane" {
  project                  = var.project_id
  name                     = "${var.name}-control-plane"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.control_plane_cidr
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_subnetwork" "compute" {
  project                  = var.project_id
  name                     = "${var.name}-compute"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.compute_cidr
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Nodes have no public IP: all outbound traffic (image pulls from quay.io / registry.redhat.io,
# Red Hat telemetry, Google APIs not covered by Private Google Access) leaves through Cloud NAT.
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # An OpenShift node opens many concurrent connections while pulling images during
  # installs and upgrades; the default 64 ports per VM is a classic source of
  # "connection timed out" on day 1.
  min_ports_per_vm                    = 1024
  enable_endpoint_independent_mapping = false

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
