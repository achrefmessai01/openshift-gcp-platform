# One google_compute_firewall per flow of the flow matrix (docs/flow-matrix.yaml).
# The matrix is the reviewed document; this module only translates it, so a change in the
# matrix is a change in the firewall and vice versa.

locals {
  flows = { for f in var.flows : f.id => f }

  resolved = {
    for id, f in local.flows : id => {
      source      = distinct(flatten([for a in f.source : lookup(var.cidr_aliases, a, [a])]))
      destination = distinct(flatten([for a in f.destination : lookup(var.cidr_aliases, a, [a])]))
    }
  }
}

resource "google_compute_firewall" "this" {
  for_each = local.flows

  project     = var.project_id
  name        = lower("${var.name_prefix}-${each.value.id}-${each.value.name}")
  network     = var.network
  description = "${each.value.id}: ${each.value.description}"
  direction   = each.value.direction
  priority    = lookup(each.value, "priority", 1000)
  disabled    = lookup(each.value, "disabled", false)

  # INGRESS rules match on source and (optionally) destination ranges; EGRESS rules on
  # destination ranges only, the source being every instance of the network.
  source_ranges      = each.value.direction == "INGRESS" ? local.resolved[each.key].source : null
  destination_ranges = local.resolved[each.key].destination

  # Rules objects from YAML do not all have the same attributes (ports is optional), so the
  # action filter is a comprehension rather than a conditional expression.
  dynamic "allow" {
    for_each = [for r in each.value.rules : r if lookup(each.value, "action", "allow") == "allow"]
    content {
      protocol = allow.value.protocol
      ports    = lookup(allow.value, "ports", null)
    }
  }

  dynamic "deny" {
    for_each = [for r in each.value.rules : r if lookup(each.value, "action", "allow") == "deny"]
    content {
      protocol = deny.value.protocol
      ports    = lookup(deny.value, "ports", null)
    }
  }

  dynamic "log_config" {
    for_each = [for enabled in [lookup(each.value, "logging", false)] : enabled if enabled]
    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}
