variable "project_id" {
  description = "Project that hosts the pipeline (the observability project). Traces and logs land here, so one project shows the whole estate."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  description = "Zone for the gateway VM. Must be in a free-tier region (us-central1, us-east1 or us-west1)."
  type        = string
  default     = "us-central1-a"
}

variable "collector_image" {
  description = "Google-Built OpenTelemetry Collector image. Pin a version; Dependabot does not track it."
  type        = string
  default     = "us-docker.pkg.dev/cloud-ops-agents-artifacts/google-cloud-opentelemetry-collector/otelcol-google:0.165.2-r.1"
}

variable "subnet_cidr" {
  description = "Range for the telemetry subnet. Only the gateway VM lives here."
  type        = string
  default     = "10.40.0.0/28"
}

variable "web_origins" {
  description = "Browser origins allowed to send real-user telemetry to the edge collector (CORS)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.web_origins : can(regex("^https://", o))])
    error_message = "Web origins must use https://."
  }
}

variable "baseline_sampling_percent" {
  description = "Share of ordinary traces kept by tail sampling. Errors, slow traces, safety-critical traces and fault-injection traces are always kept."
  type        = number
  default     = 20

  validation {
    condition     = var.baseline_sampling_percent >= 0 && var.baseline_sampling_percent <= 100
    error_message = "baseline_sampling_percent must be between 0 and 100."
  }
}

variable "publisher_members" {
  description = "Identities (serviceAccount:..., group:...) allowed to publish telemetry to the ingest topics, typically the runtime accounts of services that run a collector sidecar."
  type        = list(string)
  default     = []
}

variable "iap_ssh_members" {
  description = "Identities allowed to SSH to the gateway VM through IAP."
  type        = list(string)
  default     = []
}

variable "enable_edge" {
  description = "Deploy the public edge collector on Cloud Run for browser (real-user) and synthetic telemetry."
  type        = bool
  default     = true
}

variable "edge_max_instances" {
  description = "Upper bound on edge collector instances. Keeps a flood of browser telemetry from becoming a bill."
  type        = number
  default     = 2
}

variable "pipeline_alert_channels" {
  description = "Notification channels for the \"pipeline stalled\" alert. Empty means no alert policy (alert policies are billed per condition)."
  type        = list(string)
  default     = []
}
