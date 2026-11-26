output "topics" {
  description = "Ingest topic per signal, for sidecar configuration."
  value       = { for k, t in google_pubsub_topic.otel : k => t.id }
}

output "edge_url" {
  description = "OTLP/HTTP endpoint for browsers and synthetic users (append /v1/traces etc.)."
  value       = var.enable_edge ? google_cloud_run_v2_service.edge[0].uri : null
}

output "gateway_instance" {
  value = google_compute_instance.gateway.name
}

output "gateway_service_account" {
  value = google_service_account.gateway.email
}

output "sidecar_config" {
  description = "Collector config for service sidecars. Set OTEL_PIPELINE_PROJECT, NORTHCREST_BUSINESS_UNIT and NORTHCREST_TIER."
  value       = local.configs.sidecar
}

output "dashboard_id" {
  value = google_monitoring_dashboard.pipeline.id
}
