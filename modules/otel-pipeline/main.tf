# OpenTelemetry pipeline for the Northcrest estate. Agent -> transport ->
# gateway -> Google Cloud Observability:
#
#   services (sidecar agent) ──┐
#   browsers, synthetics ─ edge collector (Cloud Run) ─┤ Pub/Sub, one topic
#                              │                       │ per signal
#   gateway VM: host agent ─▶ gateway ◀────────────────┘
#                               │
#                               ├─ traces, logs ─▶ Telemetry API (Cloud Trace, Cloud Logging)
#                               └─ metrics ─────▶ Cloud Monitoring (workload.googleapis.com)
#
# Pub/Sub decouples producers from the gateway: projects need no network
# path to it, only publish rights, and telemetry waits in the subscription
# (up to a day) while the gateway restarts or is replaced.
# Design and cost notes: docs/opentelemetry.md.

locals {
  signals = toset(["traces", "metrics", "logs"])

  # Changing any collector config replaces the gateway VM (see gateway.tf).
  configs = {
    agent   = file("${path.module}/config/agent.yaml")
    gateway = file("${path.module}/config/gateway.yaml")
    edge    = file("${path.module}/config/edge.yaml")
    sidecar = file("${path.module}/config/sidecar.yaml")
  }

  publishers = { for pair in setproduct(tolist(local.signals), var.publisher_members) : "${pair[0]}/${pair[1]}" => {
    signal = pair[0]
    member = pair[1]
  } }
}

# --- Transport ---------------------------------------------------------------

resource "google_pubsub_topic" "otel" {
  #checkov:skip=CKV_GCP_83:Synthetic telemetry; Google-managed encryption is enough.
  for_each = local.signals

  project = var.project_id
  name    = "otel-${each.key}"

  labels = {
    component = "otel-pipeline"
    signal    = each.key
  }
}

resource "google_pubsub_subscription" "gateway" {
  for_each = local.signals

  project = var.project_id
  name    = "otel-${each.key}-gateway"
  topic   = google_pubsub_topic.otel[each.key].id

  ack_deadline_seconds = 60
  # Long enough to ride out a gateway restart or replacement, short enough
  # that a stopped gateway does not build up storage charges.
  message_retention_duration = "86400s"

  expiration_policy {
    ttl = "" # never expire, even if the gateway is off for weeks
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  labels = {
    component = "otel-pipeline"
    signal    = each.key
  }
}

# --- Identities --------------------------------------------------------------

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "otel-gateway"
  display_name = "OpenTelemetry gateway"
  description  = "Gateway VM: reads telemetry from Pub/Sub, writes to Cloud Trace, Logging and Monitoring."
}

resource "google_service_account" "edge" {
  project      = var.project_id
  account_id   = "otel-edge"
  display_name = "OpenTelemetry edge collector"
  description  = "Public Cloud Run collector: publishes browser and synthetic telemetry to Pub/Sub."
}

resource "google_project_iam_member" "gateway" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/telemetry.tracesWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = google_service_account.gateway.member
}

resource "google_pubsub_subscription_iam_member" "gateway" {
  for_each = local.signals

  project      = var.project_id
  subscription = google_pubsub_subscription.gateway[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = google_service_account.gateway.member
}

resource "google_pubsub_topic_iam_member" "edge" {
  for_each = var.enable_edge ? local.signals : toset([])

  project = var.project_id
  topic   = google_pubsub_topic.otel[each.key].name
  role    = "roles/pubsub.publisher"
  member  = google_service_account.edge.member
}

resource "google_pubsub_topic_iam_member" "publishers" {
  for_each = local.publishers

  project = var.project_id
  topic   = google_pubsub_topic.otel[each.value.signal].name
  role    = "roles/pubsub.publisher"
  member  = each.value.member
}
