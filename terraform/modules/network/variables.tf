variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "control_plane_cidr" {
  type = string
}

variable "compute_cidr" {
  type = string
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}
