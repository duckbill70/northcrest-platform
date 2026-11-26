# Public edge collector on Cloud Run: the only part of the pipeline reachable
# from the internet. Scales to zero, request-based billing, stateless.

resource "google_cloud_run_v2_service" "edge" {
  count = var.enable_edge ? 1 : 0

  project             = var.project_id
  location            = var.region
  name                = "otel-edge"
  description         = "Public OTLP/HTTP endpoint for browser and synthetic telemetry."
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  # Browsers cannot attach Google credentials, so the endpoint is public. The
  # org's default domain-restricted sharing policy forbids allUsers, so turn
  # off Cloud Run's invoker check instead of granting allUsers run.invoker.
  # The config limits what it accepts; max instances and the budget limit
  # the cost.
  #checkov:skip=CKV_GCP_102:Public by design: browsers send real-user telemetry here. See edge.yaml for the limits.
  invoker_iam_disabled = true

  template {
    service_account                  = google_service_account.edge.email
    timeout                          = "30s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = var.edge_max_instances
    }

    containers {
      image = var.collector_image
      args  = ["--config=env:OTELCOL_CONFIG"]

      ports {
        container_port = 4318
      }

      resources {
        cpu_idle          = true # request-based billing
        startup_cpu_boost = true
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "OTELCOL_CONFIG"
        value = local.configs.edge
      }
      env {
        name  = "OTEL_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "OTEL_CORS_ORIGINS"
        value = jsonencode(var.web_origins)
      }
    }
  }

  labels = {
    component = "otel-pipeline"
  }

  depends_on = [google_pubsub_topic_iam_member.edge]
}
