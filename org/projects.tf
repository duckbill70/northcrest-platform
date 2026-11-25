module "project" {
  source   = "../modules/project"
  for_each = local.projects

  project_id         = "${var.project_prefix}-${each.key}"
  name               = each.value.name
  folder_id          = google_folder.unit[each.value.folder].folder_id
  billing_account_id = var.billing_account_id
  services           = distinct(concat(local.common_services, each.value.services))

  labels = {
    business-unit = each.value.folder
    tier          = local.business_units[each.value.folder].tier
    core          = tostring(each.value.core)
    env           = "prod"
  }
}
