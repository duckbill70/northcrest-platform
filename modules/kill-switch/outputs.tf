output "topic_id" {
  description = "Pub/Sub topic for budget notifications (projects/<p>/topics/<t>)."
  value       = google_pubsub_topic.budget.id
}

output "function_name" {
  value = google_cloudfunctions2_function.kill_switch.name
}

output "service_account_email" {
  value = google_service_account.runtime.email
}

output "dry_run" {
  value = var.dry_run
}
