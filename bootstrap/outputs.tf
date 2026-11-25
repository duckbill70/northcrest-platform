output "seed_project_id" {
  value = google_project.seed.project_id
}

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Full provider resource name for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account" {
  value = google_service_account.tf_plan.email
}

output "apply_service_account" {
  value = google_service_account.tf_apply.email
}

output "github_repository_variables" {
  description = "Set these as repository variables (Settings > Secrets and variables > Actions > Variables). None of them are secrets."
  value = {
    GCP_WIF_PROVIDER    = google_iam_workload_identity_pool_provider.github.name
    GCP_TF_PLAN_SA      = google_service_account.tf_plan.email
    GCP_TF_APPLY_SA     = google_service_account.tf_apply.email
    GCP_TF_STATE_BUCKET = google_storage_bucket.tfstate.name
    GCP_SEED_PROJECT    = google_project.seed.project_id
    GCP_ORG_ID          = var.org_id
    GCP_BILLING_ACCOUNT = var.billing_account_id
    GCP_PROJECT_PREFIX  = var.project_prefix
  }
}
