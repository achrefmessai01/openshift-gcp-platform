output "zone_name" {
  value = one(google_dns_managed_zone.base[*].name)
}

output "name_servers" {
  value = flatten(google_dns_managed_zone.base[*].name_servers)
}
