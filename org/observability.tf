# One pane of glass: the observability project is the metrics scope for every
# other project, so dashboards and SLOs can span the estate.

resource "google_monitoring_monitored_project" "estate" {
  for_each = toset(local.workload_project_ids)

  metrics_scope = "locations/global/metricsScopes/${module.project["observability"].project_id}"
  name          = each.value
}

resource "google_monitoring_notification_channel" "email" {
  project      = module.project["observability"].project_id
  display_name = "Northcrest platform alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# Target for the Cloud Billing export to BigQuery. The export itself has no
# API and is switched on once in the console (Billing > Billing export).
resource "google_bigquery_dataset" "billing_export" {
  #checkov:skip=CKV_GCP_81:Google-managed encryption; billing data is not sensitive in a demo.
  project       = module.project["observability"].project_id
  dataset_id    = "billing_export"
  friendly_name = "Cloud Billing export"
  description   = "Detailed billing export, feeds the cost dashboard."
  location      = var.region

  delete_contents_on_destroy = false
}
