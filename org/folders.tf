resource "google_folder" "unit" {
  for_each = local.business_units

  display_name        = each.value.display
  parent              = "organizations/${var.org_id}"
  deletion_protection = true
}
