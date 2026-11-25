# One Northcrest project: created in its business-unit folder, linked to
# billing, with no default network and only the APIs it needs.
resource "google_project" "this" {
  project_id          = var.project_id
  name                = var.name
  folder_id           = var.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
  deletion_policy     = var.deletion_policy
  labels              = var.labels
}

resource "google_project_service" "this" {
  for_each = toset(var.services)

  project                    = google_project.this.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}
