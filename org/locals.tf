locals {
  # Business units from the concept doc. Each becomes a folder; tier drives
  # labels, policies and (later) SLOs and change rules.
  business_units = {
    customer-channels  = { display = "Customer Channels", tier = "commercial" }
    airport-operations = { display = "Airport Operations", tier = "operational" }
    flight-operations  = { display = "Flight Operations", tier = "safety-critical" }
    commercial-data    = { display = "Commercial and Data", tier = "internal" }
    platform           = { display = "Platform", tier = "shared" }
  }

  # core = true keeps billing when the kill switch fires, so the public demo,
  # monitoring and the switch itself survive. Anything else is expendable.
  projects = {
    platform = {
      name   = "Northcrest Platform"
      folder = "platform"
      core   = true
      services = [
        "artifactregistry.googleapis.com",
        "cloudbuild.googleapis.com",
        "firestore.googleapis.com",
        "run.googleapis.com",
        "secretmanager.googleapis.com",
      ]
    }
    observability = {
      name   = "Northcrest Observability"
      folder = "platform"
      core   = true
      services = [
        "artifactregistry.googleapis.com",
        "bigquery.googleapis.com",
        "bigquerydatatransfer.googleapis.com",
        "cloudbuild.googleapis.com",
        "cloudfunctions.googleapis.com",
        "cloudscheduler.googleapis.com",
        "cloudtrace.googleapis.com",
        "compute.googleapis.com",
        "eventarc.googleapis.com",
        "iap.googleapis.com",
        "logging.googleapis.com",
        "monitoring.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
        "storage.googleapis.com",
        "telemetry.googleapis.com",
      ]
    }
    customer = {
      name   = "Northcrest Customer Channels"
      folder = "customer-channels"
      core   = true
      services = [
        "artifactregistry.googleapis.com",
        "cloudfunctions.googleapis.com",
        "cloudscheduler.googleapis.com",
        "cloudtrace.googleapis.com",
        "compute.googleapis.com",
        "firebase.googleapis.com",
        "firebasehosting.googleapis.com",
        "firebaserules.googleapis.com",
        "firestore.googleapis.com",
        "iamcredentials.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
      ]
    }
    airport-ops = {
      name   = "Northcrest Airport Operations"
      folder = "airport-operations"
      core   = false
      services = [
        "cloudscheduler.googleapis.com",
        "cloudtrace.googleapis.com",
        "compute.googleapis.com",
        "firestore.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
      ]
    }
    flight-ops = {
      name   = "Northcrest Flight Operations"
      folder = "flight-operations"
      core   = false
      services = [
        "cloudscheduler.googleapis.com",
        "cloudtrace.googleapis.com",
        "compute.googleapis.com",
        "firestore.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
        "workflows.googleapis.com",
      ]
    }
    commercial = {
      name   = "Northcrest Commercial and Data"
      folder = "commercial-data"
      core   = false
      services = [
        "bigquery.googleapis.com",
        "cloudscheduler.googleapis.com",
        "compute.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
        "workflows.googleapis.com",
      ]
    }
  }

  # Services every project gets, for monitoring and cost visibility.
  # cloudresourcemanager and serviceusage must be on in each project because
  # the provider bills calls to the resource's own project
  # (user_project_override); a new project needs them enabled once by hand
  # before its first apply (see docs/bootstrap-runbook.md).
  common_services = [
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  # Where each business unit's workloads run while its own project is
  # unbilled. Flight operations is never folded in, so the safety-critical
  # tier keeps its own project and policies.
  workload_hosts = {
    platform    = "observability"
    airport-ops = "customer"
    commercial  = "observability"
  }
  workload_home = {
    for k in keys(local.projects) :
    k => contains(var.unbilled_projects, k) ? local.workload_hosts[k] : k
  }

  workload_project_ids = [for k, m in module.project : m.project_id if k != "observability" && !contains(var.unbilled_projects, k)]
  billed_project_ids   = [for k, m in module.project : m.project_id if !contains(var.unbilled_projects, k)]
  non_core_project_ids = [for k, p in local.projects : module.project[k].project_id if !p.core]
}
