# Phase 2, the passenger journey: what the booking and flight-status apps
# need from the platform. The apps themselves live in northcrest-services
# (Cloud Run APIs) and northcrest-web (React on Firebase Hosting); their
# workflows deploy with the accounts below.
#
# Everything sits in the customer project (also home to airport-ops while
# that project is unbilled). Browsers reach the APIs through Firebase
# Hosting rewrites (/api/** -> Cloud Run), so there is no CORS and no
# public Cloud Run URL to advertise.

locals {
  passenger_project = module.project["customer"].project_id

  # Cloud Run service name => runtime account ID. Service names are fixed
  # because the Hosting rewrites in northcrest-web refer to them.
  passenger_apis = {
    "booking-api"       = "booking-api"
    "flight-status-api" = "flight-status-api"
  }

  # Firebase Hosting sites. Site IDs are global, so they carry the prefix.
  passenger_sites = {
    booking = "${var.project_prefix}-booking"
    status  = "${var.project_prefix}-status"
  }

  passenger_runtime_roles = [
    "roles/cloudtrace.agent",
    "roles/datastore.user",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]

  # GitHub repositories that deploy, and the pool their tokens come through.
  wif_pool = "projects/${data.google_project.seed.number}/locations/global/workloadIdentityPools/github"
}

data "google_project" "seed" {
  project_id = "${var.project_prefix}-seed"
}

# --- Data ---------------------------------------------------------------------

# The free tier covers the (default) database only.
resource "google_firestore_database" "passenger" {
  project                 = local.passenger_project
  name                    = "(default)"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  deletion_policy         = "ABANDON"
}

# Browsers never talk to Firestore directly; only the APIs' service accounts
# do, and IAM ignores these rules. Deny every client SDK request.
resource "google_firebaserules_ruleset" "firestore_deny_all" {
  project = local.passenger_project

  source {
    files {
      name    = "firestore.rules"
      content = <<-EOT
        rules_version = '2';
        service cloud.firestore {
          match /databases/{database}/documents {
            match /{document=**} {
              allow read, write: if false;
            }
          }
        }
      EOT
    }
  }

  depends_on = [google_firestore_database.passenger]
}

resource "google_firebaserules_release" "firestore" {
  project      = local.passenger_project
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore_deny_all.name
}

# --- Images -------------------------------------------------------------------

resource "google_artifact_registry_repository" "services" {
  #checkov:skip=CKV_GCP_84:Customer-supplied keys need Cloud KMS, which is not free; Google-managed encryption is accepted (see .checkov.yaml).
  project       = local.passenger_project
  location      = var.region
  repository_id = "services"
  description   = "Container images for the Northcrest APIs."
  format        = "DOCKER"

  # 0.5 GB is free: keep only the latest few images per service.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-latest-5"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }
}

# --- Web hosting --------------------------------------------------------------

resource "google_firebase_project" "customer" {
  provider = google-beta
  project  = local.passenger_project
}

resource "google_firebase_hosting_site" "passenger" {
  provider = google-beta
  for_each = local.passenger_sites

  project = local.passenger_project
  site_id = each.value

  depends_on = [google_firebase_project.customer]
}

# --- Runtime accounts ---------------------------------------------------------

resource "google_service_account" "passenger_api" {
  for_each = local.passenger_apis

  project      = local.passenger_project
  account_id   = each.value
  display_name = "Runtime: ${each.key}"
}

resource "google_project_iam_member" "passenger_api" {
  for_each = { for pair in setproduct(keys(local.passenger_apis), local.passenger_runtime_roles) : "${pair[0]}/${pair[1]}" => {
    api  = pair[0]
    role = pair[1]
  } }

  project = local.passenger_project
  role    = each.value.role
  member  = google_service_account.passenger_api[each.value.api].member
}

# --- Deploy accounts for GitHub Actions ---------------------------------------

resource "google_service_account" "deployer" {
  for_each = toset(["services", "web"])

  project      = local.passenger_project
  account_id   = "deploy-${each.key}"
  display_name = "GitHub deploys from northcrest-${each.key}"
}

# Only jobs that declare `environment: production` in the deploying repo can
# use its deploy account, and the repos limit that environment to main. A
# pull request can't add a workflow that borrows the account. The subject is
# bound in both GitHub formats (plain names, and names with immutable IDs),
# since which one a repo's tokens carry depends on its OIDC settings.
locals {
  deploy_subjects = {
    for key, id in var.deploy_repository_ids : key => [
      "repo:${var.github_owner}/northcrest-${key}:environment:production",
      "repo:${var.github_owner}@${var.github_owner_id}/northcrest-${key}@${id}:environment:production",
    ]
  }
}

resource "google_service_account_iam_member" "deployer_wif" {
  for_each = { for pair in flatten([
    for key, subjects in local.deploy_subjects : [for i, s in subjects : { key = "${key}/${i}", repo = key, subject = s }]
  ]) : pair.key => pair }

  service_account_id = google_service_account.deployer[each.value.repo].id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.wif_pool}/subject/${each.value.subject}"
}

# run.admin rather than run.developer: the services deploy with Cloud Run's
# invoker check off (the org forbids allUsers), and turning that off needs
# run.services.setIamPolicy.
resource "google_project_iam_member" "deploy_services" {
  for_each = toset([
    "roles/run.admin",
    "roles/serviceusage.serviceUsageConsumer",
  ])

  project = local.passenger_project
  role    = each.value
  member  = google_service_account.deployer["services"].member
}

resource "google_artifact_registry_repository_iam_member" "deploy_services" {
  project    = local.passenger_project
  location   = google_artifact_registry_repository.services.location
  repository = google_artifact_registry_repository.services.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.deployer["services"].member
}

# Deploying a Cloud Run revision that runs as an account needs actAs on it.
resource "google_service_account_iam_member" "deploy_services_act_as" {
  for_each = google_service_account.passenger_api

  service_account_id = each.value.id
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deployer["services"].member
}

resource "google_project_iam_member" "deploy_web" {
  for_each = toset([
    "roles/firebasehosting.admin",
    "roles/run.viewer", # Hosting checks that rewrite targets exist
    "roles/serviceusage.serviceUsageConsumer",
  ])

  project = local.passenger_project
  role    = each.value
  member  = google_service_account.deployer["web"].member
}
