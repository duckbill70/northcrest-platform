module "project" {
  source   = "../modules/project"
  for_each = local.projects

  project_id = "${var.project_prefix}-${each.key}"
  name       = each.value.name
  folder_id  = google_folder.unit[each.value.folder].folder_id
  # Unbilled projects keep their folder, labels and IAM but get no billing
  # and no APIs (most APIs need billing). See var.unbilled_projects.
  billing_account_id = contains(var.unbilled_projects, each.key) ? null : var.billing_account_id
  services           = contains(var.unbilled_projects, each.key) ? [] : distinct(concat(local.common_services, each.value.services))

  labels = {
    business-unit = each.value.folder
    tier          = local.business_units[each.value.folder].tier
    core          = tostring(each.value.core)
    env           = "prod"
  }
}
