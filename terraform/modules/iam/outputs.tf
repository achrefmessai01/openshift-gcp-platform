output "installer_service_account_email" {
  value = google_service_account.installer.email
}

output "ci_service_account_email" {
  value = google_service_account.ci.email
}
