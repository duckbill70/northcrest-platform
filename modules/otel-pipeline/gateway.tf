# The gateway VM: the one e2-micro the free tier allows per billing account
# (us-central1, 30 GB standard disk). It runs two collectors from the same
# Google-built image: the host agent and the gateway. k6 load generation can
# share it later and send to the agent on localhost:4317.

resource "terraform_data" "collector_config" {
  # Replacing the VM is the deploy: cloud-init writes the config at boot,
  # and Pub/Sub holds telemetry while the new VM starts.
  input = sha256(join("", [local.configs.agent, local.configs.gateway, var.collector_image, tostring(var.baseline_sampling_percent)]))
}

resource "google_compute_instance" "gateway" {
  #checkov:skip=CKV_GCP_38:Customer-supplied disk keys cost money and add nothing for a stateless VM.
  project      = var.project_id
  zone         = var.zone
  name         = "otel-gateway"
  machine_type = "e2-micro" # free tier; do not change without a budget review
  description  = "OpenTelemetry host agent and estate gateway."

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
      size  = 10
      type  = "pd-standard" # free tier covers standard, not balanced
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.telemetry.id
    # No access_config: no external IP.
  }

  service_account {
    email  = google_service_account.gateway.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      agent_config              = local.configs.agent
      gateway_config            = local.configs.gateway
      image                     = var.collector_image
      project_id                = var.project_id
      baseline_sampling_percent = var.baseline_sampling_percent
    })
    # The point of this VM is to show the OpenTelemetry agent, so COS's
    # built-in logging and monitoring agents stay off (no double counting).
    google-logging-enabled    = "false"
    google-monitoring-enabled = "false"
    enable-oslogin            = "TRUE"
    block-project-ssh-keys    = "true"
    serial-port-enable        = "false"
  }

  labels = {
    component = "otel-pipeline"
    # The kill switch stops VMs labelled kill-switch=stop. This one is free
    # and keeps telemetry flowing while the switch acts, so it is exempt.
    kill-switch = "exempt"
  }

  lifecycle {
    replace_triggered_by = [terraform_data.collector_config]
  }

  depends_on = [
    google_project_iam_member.gateway,
    google_pubsub_subscription_iam_member.gateway,
  ]
}
