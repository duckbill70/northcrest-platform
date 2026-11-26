# The first service level objectives, for the passenger journey. Each one is
# computed from the RED span metrics the OTel gateway derives before tail
# sampling (modules/otel-pipeline, spanmetrics), so every request counts,
# not just the sampled traces. Only server spans count: one per request.
#
# The metrics land in the observability project as
# workload.googleapis.com/northcrest.red.{calls,duration} on a generic_task
# resource whose job label is the OTel service.name.

locals {
  red_calls    = "metric.type=\"workload.googleapis.com/northcrest.red.calls\""
  red_duration = "metric.type=\"workload.googleapis.com/northcrest.red.duration\""
  server_spans = "metric.label.\"span_kind\"=\"SPAN_KIND_SERVER\""
  span_error   = "metric.label.\"status_code\"=\"STATUS_CODE_ERROR\""

  slo_services = {
    booking = {
      display = "Booking API"
      job     = "northcrest-booking-api"
      run     = "booking-api"
    }
    status = {
      display = "Flight status API"
      job     = "northcrest-flight-status-api"
      run     = "flight-status-api"
    }
  }

  slos = {
    booking-availability = {
      service = "booking"
      name    = "Bookings succeed"
      goal    = 0.995
      kind    = "availability"
    }
    booking-latency = {
      service   = "booking"
      name      = "Booking requests answer within 500 ms"
      goal      = 0.95
      kind      = "latency"
      threshold = 500 # ms, the unit of northcrest.red.duration
    }
    status-availability = {
      service = "status"
      name    = "Flight status answers"
      goal    = 0.995
      kind    = "availability"
    }
  }

  # Burn-rate alerts in the Google SRE workbook style, sized for a 28-day
  # window: page-worthy when the budget would be gone in about two days,
  # a slower ticket when it would be gone in about a week.
  burn_alerts = {
    fast = { lookback = "3600s", threshold = 14.4, duration = "0s" }
    slow = { lookback = "21600s", threshold = 6, duration = "300s" }
  }
}

resource "google_monitoring_custom_service" "passenger" {
  for_each = local.slo_services

  project      = module.project["observability"].project_id
  service_id   = "northcrest-${each.key}"
  display_name = each.value.display

  telemetry {
    resource_name = "//run.googleapis.com/projects/${local.passenger_project}/locations/${var.region}/services/${each.value.run}"
  }
}

resource "google_monitoring_slo" "passenger" {
  for_each = local.slos

  project      = module.project["observability"].project_id
  service      = google_monitoring_custom_service.passenger[each.value.service].service_id
  slo_id       = each.key
  display_name = each.value.name

  goal                = each.value.goal
  rolling_period_days = 28

  request_based_sli {
    dynamic "good_total_ratio" {
      for_each = each.value.kind == "availability" ? [1] : []
      content {
        total_service_filter = join(" AND ", [
          local.red_calls,
          "resource.type=\"generic_task\"",
          "resource.label.\"job\"=\"${local.slo_services[each.value.service].job}\"",
          local.server_spans,
        ])
        bad_service_filter = join(" AND ", [
          local.red_calls,
          "resource.type=\"generic_task\"",
          "resource.label.\"job\"=\"${local.slo_services[each.value.service].job}\"",
          local.server_spans,
          local.span_error,
        ])
      }
    }

    dynamic "distribution_cut" {
      for_each = each.value.kind == "latency" ? [1] : []
      content {
        distribution_filter = join(" AND ", [
          local.red_duration,
          "resource.type=\"generic_task\"",
          "resource.label.\"job\"=\"${local.slo_services[each.value.service].job}\"",
          local.server_spans,
        ])
        range {
          max = each.value.threshold
        }
      }
    }
  }
}

resource "google_monitoring_alert_policy" "slo_burn" {
  for_each = { for pair in setproduct(keys(local.slos), keys(local.burn_alerts)) : "${pair[0]}/${pair[1]}" => {
    slo   = pair[0]
    speed = pair[1]
  } }

  project      = module.project["observability"].project_id
  display_name = "SLO burn (${each.value.speed}): ${local.slos[each.value.slo].name}"
  combiner     = "OR"
  severity     = each.value.speed == "fast" ? "CRITICAL" : "WARNING"

  conditions {
    display_name = "Error budget burning ${local.burn_alerts[each.value.speed].threshold}x too fast"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.passenger[each.value.slo].name}\", \"${local.burn_alerts[each.value.speed].lookback}\")"
      comparison      = "COMPARISON_GT"
      threshold_value = local.burn_alerts[each.value.speed].threshold
      duration        = local.burn_alerts[each.value.speed].duration
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    mime_type = "text/markdown"
    content   = "The ${local.slos[each.value.slo].name} SLO (${local.slos[each.value.slo].goal * 100}% over 28 days) is using its error budget ${local.burn_alerts[each.value.speed].threshold}x faster than it can afford. Open the SLO in Monitoring > SLOs, then Trace explorer filtered to ${local.slo_services[local.slos[each.value.slo].service].job} with status Error or high latency."
  }
}
