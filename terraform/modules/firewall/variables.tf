variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "network" {
  description = "Self link of the VPC network."
  type        = string
}

variable "flows" {
  description = "Flows from docs/flow-matrix.yaml (list of objects)."
  type        = any

  validation {
    condition     = alltrue([for f in var.flows : contains(["INGRESS", "EGRESS"], f.direction)])
    error_message = "Every flow must have direction INGRESS or EGRESS."
  }

  validation {
    condition     = length(distinct([for f in var.flows : f.id])) == length(var.flows)
    error_message = "Flow ids must be unique."
  }
}

variable "cidr_aliases" {
  description = "Alias name => list of CIDRs, used to resolve symbolic sources/destinations."
  type        = map(list(string))
}
