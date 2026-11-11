# GCP landing zone for an OpenShift Container Platform cluster installed with the IPI
# installer into an existing VPC (platform.gcp.network / controlPlaneSubnet / computeSubnet).
#
#   network   VPC, two subnets, Cloud Router + Cloud NAT (nodes have no public IP)
#   firewall  VPC firewall rules generated from docs/flow-matrix.yaml (the reviewed flow matrix)
#   iam       required Google APIs, installer service account and roles, CI service account
#   dns       public managed zone for the cluster base domain
#   storage   GCS bucket backing the internal image registry

locals {
  flow_matrix = yamldecode(file("${path.module}/${var.flow_matrix_path}"))

  # Aliases referenced by the flow matrix, resolved to concrete CIDRs here so the matrix
  # itself stays environment-independent. Google ranges: health checkers and IAP TCP forwarding.
  cidr_aliases = {
    control_plane     = [var.control_plane_cidr]
    compute           = [var.compute_cidr]
    admin             = var.admin_cidrs
    internet          = ["0.0.0.0/0"]
    gcp_health_checks = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]
    gcp_iap           = ["35.235.240.0/20"]
  }

  cluster_fqdn = "${var.name}.${var.base_domain}"
}

module "iam" {
  source = "./modules/iam"

  project_id  = var.project_id
  name        = var.name
  enable_apis = var.enable_apis
}

module "network" {
  source = "./modules/network"

  project_id         = var.project_id
  name               = var.name
  region             = var.region
  control_plane_cidr = var.control_plane_cidr
  compute_cidr       = var.compute_cidr
  enable_flow_logs   = var.enable_flow_logs

  depends_on = [module.iam]
}

module "firewall" {
  source = "./modules/firewall"

  project_id   = var.project_id
  name_prefix  = var.name
  network      = module.network.network_self_link
  flows        = local.flow_matrix.flows
  cidr_aliases = local.cidr_aliases
}

module "dns" {
  source = "./modules/dns"

  project_id  = var.project_id
  base_domain = var.base_domain
  create      = var.create_dns_zone
  labels      = var.labels

  depends_on = [module.iam]
}

module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  name        = var.name
  region      = var.region
  labels      = var.labels
  ci_sa_email = module.iam.ci_service_account_email

  depends_on = [module.iam]
}
