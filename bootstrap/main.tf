locals {
  seed_project_id = "${var.project_prefix}-seed"

  # APIs the seed project needs. Org-level calls made by the Terraform service
  # accounts (folders, org policy, budgets) are billed and quota-checked
  # against this project, the accounts' home, so their APIs must be on here.
  seed_services = [
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudidentity.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "orgpolicy.googleapis.com",
    # Pub/Sub subscription IAM calls ignore user_project_override and are
    # quota-checked here, not in the subscription's project.
    "pubsub.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
}

resource "google_project" "seed" {
  name                = "Northcrest Seed"
  project_id          = local.seed_project_id
  org_id              = var.org_id
  billing_account     = var.billing_account_id
  auto_create_network = false
  deletion_policy     = "PREVENT"

  labels = {
    business-unit = "platform"
    tier          = "internal"
    core          = "true"
    managed-by    = "terraform-bootstrap"
  }
}

resource "google_project_service" "seed" {
  for_each = toset(local.seed_services)

  project            = google_project.seed.project_id
  service            = each.value
  disable_on_destroy = false
}
