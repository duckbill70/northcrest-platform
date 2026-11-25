# Human access goes to groups, never to individual users, and is additive
# (iam_member) so Terraform never removes bindings it does not own, such as
# the super admin's.

locals {
  folder_ids = { for k, f in google_folder.unit : k => f.name }

  org_roles = {
    org_admins = [
      "roles/resourcemanager.organizationAdmin",
      "roles/orgpolicy.policyAdmin",
      "roles/resourcemanager.folderAdmin",
      "roles/billing.projectManager",
    ]
    sre = [
      "roles/viewer",
      "roles/logging.viewer",
      "roles/monitoring.viewer",
      "roles/cloudsupport.techSupportViewer",
    ]
  }

  org_bindings = flatten([
    for group, roles in local.org_roles : [
      for role in roles : {
        key    = "${group}/${role}"
        role   = role
        member = "group:${var.groups[group]}"
      }
    ] if var.groups[group] != ""
  ])

  # Developers deploy to commercial, operational and internal folders.
  # Flight operations is read-only for everyone: changes arrive only through
  # CI with two approvals (see the PR template and CODEOWNERS).
  developer_folders = ["customer-channels", "airport-operations", "commercial-data"]

  folder_bindings = flatten([
    var.groups.developers == "" ? [] : [
      for pair in setproduct(local.developer_folders, ["roles/viewer", "roles/run.developer", "roles/logging.viewer"]) : {
        key    = "developers/${pair[0]}/${pair[1]}"
        folder = local.folder_ids[pair[0]]
        role   = pair[1]
        member = "group:${var.groups.developers}"
      }
    ],
    var.groups.developers == "" ? [] : [{
      key    = "developers/flight-operations/roles/viewer"
      folder = local.folder_ids["flight-operations"]
      role   = "roles/viewer"
      member = "group:${var.groups.developers}"
    }],
    var.groups.safety_approvers == "" ? [] : [{
      key    = "safety_approvers/flight-operations/roles/viewer"
      folder = local.folder_ids["flight-operations"]
      role   = "roles/viewer"
      member = "group:${var.groups.safety_approvers}"
    }],
  ])
}

resource "google_organization_iam_member" "group" {
  for_each = { for b in local.org_bindings : b.key => b }

  org_id = var.org_id
  role   = each.value.role
  member = each.value.member
}

resource "google_folder_iam_member" "group" {
  for_each = { for b in local.folder_bindings : b.key => b }

  folder = each.value.folder
  role   = each.value.role
  member = each.value.member
}

# SRE owns monitoring config in the observability project.
resource "google_project_iam_member" "sre_monitoring" {
  count = var.groups.sre == "" ? 0 : 1

  project = module.project["observability"].project_id
  role    = "roles/monitoring.editor"
  member  = "group:${var.groups.sre}"
}
