output "folders" {
  value = { for k, f in google_folder.unit : k => f.name }
}

output "projects" {
  value = { for k, m in module.project : k => m.project_id }
}

output "workload_projects" {
  description = "Project each business unit deploys to. Differs from projects while a unit's own project is unbilled."
  value       = { for k, home in local.workload_home : k => module.project[home].project_id }
}

output "non_core_projects" {
  description = "Projects that lose billing when the kill switch fires."
  value       = local.non_core_project_ids
}

output "budget_topic" {
  value = module.kill_switch.topic_id
}

output "alert_channel" {
  value = google_monitoring_notification_channel.email.id
}

output "otel_edge_url" {
  description = "Public OTLP/HTTP endpoint for browser and synthetic telemetry."
  value       = module.otel.edge_url
}

output "otel_topics" {
  description = "Pub/Sub ingest topics for collector sidecars."
  value       = module.otel.topics
}
