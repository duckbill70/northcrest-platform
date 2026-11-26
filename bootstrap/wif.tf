# Workload Identity Federation: GitHub Actions exchanges its OIDC token for
# short-lived Google credentials, so no service account key exists anywhere.

resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.seed.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "OIDC federation for the Northcrest GitHub repositories."

  depends_on = [google_project_service.seed]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  #checkov:skip=CKV_GCP_125:The pool admits only Northcrest repos by owner ID; per-account subject/environment limits are enforced in the IAM bindings below.
  project                            = google_project.seed.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.actor"               = "assertion.actor"
  }

  # Reject tokens from any repository outside the Northcrest set, checked
  # against the owner's numeric ID as well as the repository name.
  attribute_condition = join(" && ", [
    "assertion.repository_owner_id == '${var.github_owner_id}'",
    "assertion.repository in [${join(", ", [for r in var.github_repositories : "'${var.github_owner}/${r}'"])}]",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  pool_name = google_iam_workload_identity_pool.github.name

  # Any workflow run in the platform repo (pull requests, scheduled drift checks).
  plan_principal = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository/${var.github_owner}/${var.platform_repository}"

  # GitHub's OIDC subject prefix. Repositories with immutable subjects embed
  # the owner and repository IDs.
  subject_repo = (
    var.platform_repository_id == ""
    ? "repo:${var.github_owner}/${var.platform_repository}"
    : "repo:${var.github_owner}@${var.github_owner_id}/${var.platform_repository}@${var.platform_repository_id}"
  )

  # Only jobs that declare `environment: production`, which GitHub gates
  # behind a required reviewer.
  apply_principal = "principal://iam.googleapis.com/${local.pool_name}/subject/${local.subject_repo}:environment:${var.apply_environment}"
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.plan_principal
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.apply_principal
}
