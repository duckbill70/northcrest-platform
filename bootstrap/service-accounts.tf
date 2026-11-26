resource "google_service_account" "tf_plan" {
  project      = google_project.seed.project_id
  account_id   = "tf-plan"
  display_name = "Terraform plan (read-only)"
  description  = "Used by pull request and drift workflows. Cannot change anything."
}

resource "google_service_account" "tf_apply" {
  project      = google_project.seed.project_id
  account_id   = "tf-apply"
  display_name = "Terraform apply"
  description  = "Used only by apply jobs in the protected GitHub Environment."
}

locals {
  # Read-only view of the whole org, including IAM and org policies, so plans
  # can refresh every resource. serviceUsageConsumer lets the provider bill
  # each call to the resource's own project (user_project_override in org/).
  plan_org_roles = [
    "roles/browser",
    "roles/iam.securityReviewer",
    "roles/orgpolicy.policyViewer",
    "roles/resourcemanager.folderViewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/viewer",
  ]

  # Enough to build the hierarchy and own every project it creates.
  # roles/iam.securityAdmin is the most powerful grant: it can change org IAM,
  # which is why this account is reachable only from the protected
  # environment.
  apply_org_roles = [
    "roles/billing.projectManager",
    "roles/iam.securityAdmin",
    "roles/orgpolicy.policyAdmin",
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.projectDeleter",
    "roles/serviceusage.serviceUsageConsumer",
  ]
}

resource "google_organization_iam_member" "plan" {
  #checkov:skip=CKV_GCP_115:roles/viewer is read-only; plan needs to refresh every resource type in the org.
  for_each = toset(local.plan_org_roles)

  org_id = var.org_id
  role   = each.value
  member = google_service_account.tf_plan.member
}

resource "google_organization_iam_member" "apply" {
  #checkov:skip=CKV_GCP_45:The apply account manages org IAM; it is reachable only from the protected GitHub environment.
  for_each = toset(local.apply_org_roles)

  org_id = var.org_id
  role   = each.value
  member = google_service_account.tf_apply.member
}

# Billing account: apply links projects and manages budgets; plan reads them.
resource "google_billing_account_iam_member" "apply_user" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.user"
  member             = google_service_account.tf_apply.member
}

resource "google_billing_account_iam_member" "apply_costs" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.costsManager"
  member             = google_service_account.tf_apply.member
}

resource "google_billing_account_iam_member" "plan_viewer" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.viewer"
  member             = google_service_account.tf_plan.member
}

# Org-level calls (folders, org policy, budgets) are billed to the seed.
resource "google_project_iam_member" "quota_consumer" {
  for_each = {
    plan  = google_service_account.tf_plan.member
    apply = google_service_account.tf_apply.member
  }

  project = google_project.seed.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = each.value
}
