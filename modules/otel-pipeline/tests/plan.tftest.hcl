# Offline tests: `terraform test` in modules/otel-pipeline. The Google
# provider is mocked. These pin the decisions that keep the pipeline inside
# the free tier and off the public internet.

mock_provider "google" {
  override_during = plan

  mock_resource "google_service_account" {
    defaults = {
      email  = "otel@ncair-test-observability.iam.gserviceaccount.com"
      member = "serviceAccount:otel@ncair-test-observability.iam.gserviceaccount.com"
      id     = "projects/ncair-test-observability/serviceAccounts/otel@ncair-test-observability.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_pubsub_topic" {
    defaults = {
      id = "projects/ncair-test-observability/topics/otel"
    }
  }
}

variables {
  project_id  = "ncair-test-observability"
  web_origins = ["https://ncair-test-customer.web.app"]
}

run "one_topic_and_subscription_per_signal" {
  command = plan

  assert {
    condition     = toset(keys(google_pubsub_topic.otel)) == toset(["traces", "metrics", "logs"])
    error_message = "Expected one topic per signal."
  }

  assert {
    condition     = alltrue([for s in google_pubsub_subscription.gateway : s.message_retention_duration == "86400s"])
    error_message = "Subscriptions should keep telemetry for one day, no longer."
  }
}

run "gateway_stays_in_free_tier" {
  command = plan

  assert {
    condition     = google_compute_instance.gateway.machine_type == "e2-micro"
    error_message = "The gateway must be the free-tier e2-micro."
  }

  assert {
    condition     = startswith(google_compute_instance.gateway.zone, "us-central1-")
    error_message = "The gateway must run in us-central1 (free tier, region lock)."
  }

  assert {
    condition = (
      google_compute_instance.gateway.boot_disk[0].initialize_params[0].type == "pd-standard" &&
      google_compute_instance.gateway.boot_disk[0].initialize_params[0].size <= 30
    )
    error_message = "Free tier covers up to 30 GB of standard persistent disk."
  }

  assert {
    condition     = google_compute_instance.gateway.labels["kill-switch"] != "stop"
    error_message = "The kill switch must not stop the telemetry gateway."
  }
}

run "gateway_is_private" {
  command = plan

  assert {
    condition     = length(google_compute_instance.gateway.network_interface[0].access_config) == 0
    error_message = "The gateway VM must not have an external IP."
  }

  assert {
    condition     = google_compute_subnetwork.telemetry.private_ip_google_access
    error_message = "Without an external IP the VM needs Private Google Access to reach Google APIs."
  }

  assert {
    condition     = google_compute_firewall.iap_ssh.source_ranges == toset(["35.235.240.0/20"])
    error_message = "SSH must only be reachable through IAP."
  }
}

run "gateway_boots_both_collectors" {
  command = plan

  assert {
    condition = alltrue([
      for s in ["otel-agent.service", "otel-gateway.service", "tail_sampling:", "spanmetrics:", "hostmetrics:"] :
      strcontains(google_compute_instance.gateway.metadata["user-data"], s)
    ])
    error_message = "cloud-init must install the agent and gateway with their configs."
  }

  assert {
    condition     = strcontains(google_compute_instance.gateway.metadata["user-data"], "OTEL_BASELINE_SAMPLING_PERCENT=20")
    error_message = "The baseline sampling rate must reach the gateway."
  }

  assert {
    condition     = strcontains(google_compute_instance.gateway.metadata["user-data"], "OTEL_HOST_ROOT=/hostfs")
    error_message = "The host agent must read host metrics from the /hostfs mount."
  }
}

run "edge_is_bounded_and_stateless" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.edge[0].template[0].scaling[0].max_instance_count <= 2
    error_message = "The public edge must be capped at a small number of instances."
  }

  assert {
    condition     = google_cloud_run_v2_service.edge[0].template[0].containers[0].resources[0].cpu_idle
    error_message = "The edge must use request-based billing (cpu_idle)."
  }

  assert {
    condition     = google_cloud_run_v2_service.edge[0].template[0].scaling[0].min_instance_count == 0
    error_message = "The edge must scale to zero."
  }

  assert {
    condition = (
      [for e in google_cloud_run_v2_service.edge[0].template[0].containers[0].env : e.value if e.name == "OTEL_CORS_ORIGINS"][0] ==
      jsonencode(["https://ncair-test-customer.web.app"])
    )
    error_message = "CORS origins must be passed to the edge collector."
  }
}

run "edge_can_be_disabled" {
  command = plan

  variables {
    enable_edge = false
  }

  assert {
    condition     = length(google_cloud_run_v2_service.edge) == 0 && length(google_cloud_run_v2_service_iam_member.edge_public) == 0
    error_message = "enable_edge = false must remove the public endpoint."
  }
}

run "publishers_get_every_topic" {
  command = plan

  variables {
    publisher_members = ["serviceAccount:booking@ncair-test-customer.iam.gserviceaccount.com"]
  }

  assert {
    condition     = length(google_pubsub_topic_iam_member.publishers) == 3
    error_message = "Each publisher needs publish rights on all three topics."
  }
}

run "no_alert_without_channels" {
  command = plan

  assert {
    condition     = length(google_monitoring_alert_policy.pipeline_stalled) == 0
    error_message = "Alert policies are billed; none should exist unless channels are given."
  }
}

run "rejects_http_origins" {
  command = plan

  variables {
    web_origins = ["http://example.com"]
  }

  expect_failures = [var.web_origins]
}
