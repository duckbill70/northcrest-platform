# Budget kill switch. Budgets only send notifications; this turns a budget
# notification into action:
#   >= stop_threshold   stop labelled VMs and pause load-generator jobs
#   >= detach_threshold detach billing from non-core projects
# Core projects (seed, platform, observability, customer) keep billing so the
# public demo and this switch keep working.

resource "google_pubsub_topic" "budget" {
  #checkov:skip=CKV_GCP_83:Budget notifications carry no sensitive data; Google-managed encryption is enough.
  project = var.project_id
  name    = "budget-notifications"

  message_retention_duration = "86400s"
}

# --- Identities -------------------------------------------------------------

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "kill-switch"
  display_name = "Budget kill switch"
}

resource "google_service_account" "build" {
  project      = var.project_id
  account_id   = "kill-switch-build"
  display_name = "Budget kill switch build"
}

resource "google_project_iam_member" "build" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
  ])

  project = var.project_id
  role    = each.value
  member  = google_service_account.build.member
}

# Stop VMs in every target project.
resource "google_project_iam_member" "compute" {
  for_each = toset(var.target_project_ids)

  project = each.value
  role    = "roles/compute.instanceAdmin.v1"
  member  = google_service_account.runtime.member
}

# Pause load-generator schedules in every target project.
resource "google_project_iam_member" "scheduler" {
  for_each = toset(var.target_project_ids)

  project = each.value
  role    = "roles/cloudscheduler.admin"
  member  = google_service_account.runtime.member
}

# Detach billing only where it is allowed to.
resource "google_project_iam_member" "billing" {
  for_each = toset(var.non_core_project_ids)

  project = each.value
  role    = "roles/billing.projectManager"
  member  = google_service_account.runtime.member
}

# Eventarc checks that the trigger's account may use the project.
resource "google_project_iam_member" "service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = google_service_account.runtime.member
}

# --- Source -----------------------------------------------------------------

resource "google_storage_bucket" "source" {
  #checkov:skip=CKV_GCP_62:Access logging not needed for function source.
  #checkov:skip=CKV_GCP_78:Versioning not needed; source is rebuilt from git.
  project                     = var.project_id
  name                        = "${var.project_id}-fn-source"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.root}/.build/kill-switch.zip"
  excludes    = ["__pycache__", "test_main.py"]
}

resource "google_storage_bucket_object" "source" {
  # Content hash in the name forces a redeploy when the code changes.
  name   = "kill-switch-${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.source.output_path
}

# --- Function ---------------------------------------------------------------

resource "google_cloudfunctions2_function" "kill_switch" {
  project     = var.project_id
  location    = var.region
  name        = "budget-kill-switch"
  description = "Stops load and detaches billing from non-core projects when the budget is exceeded."

  build_config {
    runtime         = "python312"
    entry_point     = "handle_budget"
    service_account = google_service_account.build.id

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 0
    available_memory               = "256M"
    timeout_seconds                = 120
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.runtime.email

    environment_variables = {
      DRY_RUN              = tostring(var.dry_run)
      STOP_THRESHOLD       = tostring(var.stop_threshold)
      DETACH_THRESHOLD     = tostring(var.detach_threshold)
      TARGET_PROJECTS      = join(",", var.target_project_ids)
      NON_CORE_PROJECTS    = join(",", var.non_core_project_ids)
      REGION               = var.region
      VM_LABEL             = var.vm_label
      SCHEDULER_JOB_PREFIX = var.scheduler_job_prefix
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.budget.id
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = google_service_account.runtime.email
  }

  depends_on = [google_project_iam_member.build, google_project_iam_member.service_usage]
}

# The Eventarc trigger calls the function as the runtime account.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.kill_switch.name
  role     = "roles/run.invoker"
  member   = google_service_account.runtime.member
}
