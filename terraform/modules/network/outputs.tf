output "network_name" {
  value = google_compute_network.vpc.name
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "control_plane_subnet_name" {
  value = google_compute_subnetwork.control_plane.name
}

output "compute_subnet_name" {
  value = google_compute_subnetwork.compute.name
}

output "compute_subnet_self_link" {
  value = google_compute_subnetwork.compute.self_link
}

output "nat_name" {
  value = google_compute_router_nat.nat.name
}
