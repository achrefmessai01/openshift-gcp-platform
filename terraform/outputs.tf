output "network_name" {
  description = "VPC network name (install-config platform.gcp.network)."
  value       = module.network.network_name
}

output "control_plane_subnet" {
  description = "Control-plane subnet name (install-config platform.gcp.controlPlaneSubnet)."
  value       = module.network.control_plane_subnet_name
}

output "compute_subnet" {
  description = "Compute subnet name (install-config platform.gcp.computeSubnet)."
  value       = module.network.compute_subnet_name
}

output "nat_name" {
  description = "Cloud NAT gateway name."
  value       = module.network.nat_name
}

output "installer_service_account" {
  description = "Service account used by openshift-install (create a key or impersonate it)."
  value       = module.iam.installer_service_account_email
}

output "ci_service_account" {
  description = "Read-only service account for pipelines (terraform plan, inventory checks)."
  value       = module.iam.ci_service_account_email
}

output "dns_name_servers" {
  description = "Name servers of the public zone; delegate base_domain to them at the registrar."
  value       = module.dns.name_servers
}

output "registry_bucket" {
  description = "GCS bucket for the OpenShift internal image registry."
  value       = module.storage.registry_bucket_name
}

output "firewall_rules" {
  description = "Firewall rules created from the flow matrix (id => rule name)."
  value       = module.firewall.rule_names
}

output "bastion_name" {
  description = "Bastion instance name, when created (gcloud compute ssh --tunnel-through-iap)."
  value       = one(google_compute_instance.bastion[*].name)
}

# Everything install/render-install-config.sh needs, in one place.
output "install_config" {
  description = "Values consumed by install/render-install-config.sh."
  value = {
    cluster_name         = var.name
    base_domain          = var.base_domain
    project_id           = var.project_id
    region               = var.region
    network              = module.network.network_name
    control_plane_subnet = module.network.control_plane_subnet_name
    compute_subnet       = module.network.compute_subnet_name
    machine_cidr         = var.machine_cidr
    api_fqdn             = "api.${local.cluster_fqdn}"
    apps_domain          = "apps.${local.cluster_fqdn}"
  }
}
