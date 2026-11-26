# Monitoring the monitoring: a dashboard for the pipeline itself, built from
# free Google Cloud system metrics plus the gateway's own counters.

locals {
  pubsub_backlog = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" resource.type=\"pubsub_subscription\" resource.label.\"subscription_id\"=monitoring.regex.full_match(\"otel-.*-gateway\")"

  dashboard_tiles = [
    {
      title   = "Telemetry waiting for the gateway (messages)"
      filter  = local.pubsub_backlog
      reducer = "REDUCE_SUM"
      group   = ["resource.label.subscription_id"]
      align   = "ALIGN_MEAN"
    },
    {
      title   = "Oldest unprocessed telemetry (seconds)"
      filter  = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\" resource.label.\"subscription_id\"=monitoring.regex.full_match(\"otel-.*-gateway\")"
      reducer = "REDUCE_MAX"
      group   = ["resource.label.subscription_id"]
      align   = "ALIGN_MAX"
    },
    {
      title   = "Published to the pipeline (requests/s)"
      filter  = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" resource.type=\"pubsub_topic\" resource.label.\"topic_id\"=monitoring.regex.full_match(\"otel-.*\")"
      reducer = "REDUCE_SUM"
      group   = ["resource.label.topic_id"]
      align   = "ALIGN_RATE"
    },
    {
      title   = "Edge collector requests (by response code)"
      filter  = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.\"service_name\"=\"otel-edge\""
      reducer = "REDUCE_SUM"
      group   = ["metric.label.response_code_class"]
      align   = "ALIGN_RATE"
    },
    {
      title   = "Gateway VM CPU (host agent)"
      filter  = "metric.type=\"workload.googleapis.com/system.cpu.utilization\" resource.type=\"gce_instance\""
      reducer = "REDUCE_SUM"
      group   = ["metric.label.state"]
      align   = "ALIGN_MEAN"
    },
    {
      title   = "Gateway VM memory (host agent)"
      filter  = "metric.type=\"workload.googleapis.com/system.memory.utilization\" resource.type=\"gce_instance\""
      reducer = "REDUCE_SUM"
      group   = ["metric.label.state"]
      align   = "ALIGN_MEAN"
    },
    {
      title   = "Requests per service (RED, from spans)"
      filter  = "metric.type=\"workload.googleapis.com/northcrest.red.calls\""
      reducer = "REDUCE_SUM"
      group   = ["resource.label.job", "metric.label.status_code"]
      align   = "ALIGN_RATE"
    },
    {
      title   = "Spans exported by the gateway"
      filter  = "metric.type=starts_with(\"workload.googleapis.com/otelcol_exporter_sent_spans\")"
      reducer = "REDUCE_SUM"
      group   = ["metric.label.exporter"]
      align   = "ALIGN_RATE"
    },
  ]
}

resource "google_monitoring_dashboard" "pipeline" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "OpenTelemetry pipeline"
    labels      = { otel-pipeline = "" }
    mosaicLayout = {
      columns = 12
      tiles = [for i, t in local.dashboard_tiles : {
        xPos   = (i % 2) * 6
        yPos   = floor(i / 2) * 4
        width  = 6
        height = 4
        widget = {
          title = t.title
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = t.filter
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = t.align
                    crossSeriesReducer = t.reducer
                    groupByFields      = t.group
                  }
                }
              }
            }]
          }
        }
      }]
    }
  })
}

# Optional: alert when the gateway stops draining its subscriptions. Off
# unless channels are given, because alert policies are billed.
resource "google_monitoring_alert_policy" "pipeline_stalled" {
  count = length(var.pipeline_alert_channels) > 0 ? 1 : 0

  project      = var.project_id
  display_name = "OpenTelemetry pipeline stalled"
  combiner     = "OR"

  conditions {
    display_name = "Telemetry older than 10 minutes is waiting in Pub/Sub"

    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\" resource.label.\"subscription_id\"=monitoring.regex.full_match(\"otel-.*-gateway\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 600
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "The gateway VM `otel-gateway` is not reading telemetry from Pub/Sub. Check that it is running, then `sudo journalctl -u otel-gateway` over IAP SSH. Telemetry is kept for 24 hours. Runbook: docs/opentelemetry.md."
  }

  notification_channels = var.pipeline_alert_channels
}
