# A small VPC for the gateway VM. No external IP and no Cloud NAT (NAT is
# billed by the hour): Private Google Access lets the VM reach Pub/Sub, the
# Telemetry API, Cloud Monitoring and Artifact Registry (for the collector
# image) over Google's network, and nothing else.

resource "google_compute_network" "telemetry" {
  project                 = var.project_id
  name                    = "telemetry"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "telemetry" {
  #checkov:skip=CKV_GCP_26:VPC flow logs are billable log volume; one VM, no east-west traffic.
  project                  = var.project_id
  name                     = "telemetry-${var.region}"
  region                   = var.region
  network                  = google_compute_network.telemetry.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# SSH only through Identity-Aware Proxy, with OS Login (org policy).
resource "google_compute_firewall" "iap_ssh" {
  project   = var.project_id
  name      = "telemetry-allow-iap-ssh"
  network   = google_compute_network.telemetry.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.gateway.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_project_iam_member" "iap_ssh" {
  for_each = toset(var.iap_ssh_members)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

resource "google_project_iam_member" "os_login" {
  for_each = toset(var.iap_ssh_members)

  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = each.value
}

# OS Login on a VM that runs as a service account also needs permission to
# act as that account.
resource "google_service_account_iam_member" "iap_ssh_act_as" {
  for_each = toset(var.iap_ssh_members)

  service_account_id = google_service_account.gateway.id
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
