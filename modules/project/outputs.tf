output "project_id" {
  value = google_project.this.project_id
  # Callers usually want the APIs ready before they create resources.
  depends_on = [google_project_service.this]
}

output "number" {
  value = google_project.this.number
}

output "billed" {
  description = "Whether the project is linked to a billing account."
  value       = var.billing_account_id != null
}
