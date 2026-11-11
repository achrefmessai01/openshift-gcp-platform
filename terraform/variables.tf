variable "project_id" {
  description = "GCP project that hosts the OpenShift cluster."
  type        = string
}

variable "region" {
  description = "GCP region for the VPC subnets, Cloud NAT and the cluster."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone for zonal resources (bastion host)."
  type        = string
  default     = "europe-west1-b"
}

variable "name" {
  description = "Short name used as a prefix for every resource and as the OpenShift cluster name."
  type        = string
  default     = "ocp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.name))
    error_message = "name must be 2-15 characters, lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "base_domain" {
  description = "Public DNS base domain of the cluster (api.<name>.<base_domain>, *.apps.<name>.<base_domain>)."
  type        = string
}

variable "create_dns_zone" {
  description = "Create the Cloud DNS public managed zone for base_domain (delegate it from the registrar afterwards)."
  type        = bool
  default     = true
}

variable "control_plane_cidr" {
  description = "CIDR of the control-plane subnet."
  type        = string
  default     = "10.10.0.0/22"
}

variable "compute_cidr" {
  description = "CIDR of the compute (worker) subnet."
  type        = string
  default     = "10.10.4.0/22"
}

variable "machine_cidr" {
  description = "Machine network declared to the OpenShift installer; must contain both subnets."
  type        = string
  default     = "10.10.0.0/16"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the OpenShift API (6443): administration networks, VPN egress, CI runners."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must list at least one CIDR and must not be 0.0.0.0/0; keep the API behind known networks."
  }
}

variable "flow_matrix_path" {
  description = "Path to the flow matrix (YAML) that drives the VPC firewall rules."
  type        = string
  default     = "../docs/flow-matrix.yaml"
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs on both subnets (useful for flow-matrix reviews and troubleshooting)."
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Enable the Google APIs required by the OpenShift installer."
  type        = bool
  default     = true
}

variable "create_bastion" {
  description = "Create a small bastion VM (no public IP, reached through IAP TCP forwarding)."
  type        = bool
  default     = false
}

variable "bastion_machine_type" {
  description = "Machine type of the bastion VM."
  type        = string
  default     = "e2-micro"
}

variable "labels" {
  description = "Labels applied to every labelable resource."
  type        = map(string)
  default = {
    owner       = "platform-team"
    managed-by  = "terraform"
    application = "openshift"
  }
}
