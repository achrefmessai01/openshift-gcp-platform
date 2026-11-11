output "rule_names" {
  description = "Flow id => firewall rule name."
  value       = { for id, r in google_compute_firewall.this : id => r.name }
}
