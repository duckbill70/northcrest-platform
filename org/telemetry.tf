# OpenTelemetry pipeline for the whole estate, hosted in the observability
# project. See modules/otel-pipeline and docs/opentelemetry.md.

module "otel" {
  source = "../modules/otel-pipeline"

  project_id = module.project["observability"].project_id
  region     = var.region
  zone       = "${var.region}-a"

  # Firebase Hosting default domains for the customer apps, plus any custom
  # domain (for example the clearwatertech.co subdomain) once it exists.
  web_origins = concat(
    [
      "https://${module.project["customer"].project_id}.web.app",
      "https://${module.project["customer"].project_id}.firebaseapp.com",
    ],
    flatten([for site in local.passenger_sites : ["https://${site}.web.app", "https://${site}.firebaseapp.com"]]),
    var.otel.extra_web_origins,
  )

  baseline_sampling_percent = var.otel.baseline_sampling_percent
  # The passenger APIs run the collector sidecar, so they publish telemetry.
  publisher_members = concat(
    [for sa in google_service_account.passenger_api : sa.member],
    var.otel.publisher_members,
  )
  iap_ssh_members         = var.groups.sre == "" ? [] : ["group:${var.groups.sre}"]
  pipeline_alert_channels = var.otel.pipeline_alert ? [google_monitoring_notification_channel.email.id] : []
}
