output "folders" {
  value = { for k, f in google_folder.unit : k => f.name }
}

output "projects" {
  value = { for k, m in module.project : k => m.project_id }
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
