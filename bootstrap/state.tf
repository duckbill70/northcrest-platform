# Versioned bucket for all Terraform state. us-central1 keeps it in the
# Cloud Storage free tier (5 GB-months).
resource "google_storage_bucket" "tfstate" {
  #checkov:skip=CKV_GCP_62:Access logging would cost more than the bucket; audit logs cover access.
  name                        = "${var.project_prefix}-tfstate"
  project                     = google_project.seed.project_id
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  # Keep the 20 most recent previous versions of each state file.
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.seed]
}

resource "google_storage_bucket_iam_member" "tfstate_apply" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.tf_apply.member
}

# Plan runs with -lock=false, so read access is enough.
resource "google_storage_bucket_iam_member" "tfstate_plan" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.tf_plan.member
}
