variable "project_id" {
  type = string
}

variable "base_domain" {
  type = string
}

variable "create" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
