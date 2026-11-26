variable "org_id" {
  description = "Numeric Organization ID."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "project_prefix" {
  description = "Same prefix used in bootstrap/, for example \"ncair-7f3k\"."
  type        = string

  validation {
    condition     = alltrue([for k in keys(local.projects) : length("${var.project_prefix}-${k}") <= 30])
    error_message = "project_prefix is too long: every <prefix>-<project> ID must be 30 characters or fewer."
  }
}

variable "unbilled_projects" {
  description = "Projects kept without billing because the billing account has hit its linked-project limit (the Free Trial allows 5, including the seed). Their workloads run in the project named in local.workload_home until they are split back out: empty this set once the limit is raised."
  type        = set(string)
  default     = ["airport-ops", "commercial"]

  validation {
    condition     = alltrue([for k in var.unbilled_projects : contains(["platform", "airport-ops", "commercial"], k)])
    error_message = "Only platform, airport-ops and commercial can be left unbilled; observability, customer and flight-ops host the others."
  }
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "directory_customer_id" {
  description = "Cloud Identity customer ID (Admin console > Account settings, starts with C). Enables domain-restricted sharing on the flight operations folder. Leave empty to skip."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Address for budget and platform alerts."
  type        = string
}

variable "currency_code" {
  description = "Must match the billing account currency."
  type        = string
  default     = "GBP"
}

variable "monthly_budget" {
  description = "Whole-estate monthly budget in currency_code. Measured before credits, so it also guards the trial credit."
  type        = number
  default     = 10
}

variable "folder_budgets" {
  description = "Monthly budget per business-unit folder (email alerts only)."
  type        = map(number)
  default = {
    customer-channels  = 3
    airport-operations = 2
    flight-operations  = 2
    commercial-data    = 2
    platform           = 4
  }
}

variable "kill_switch_dry_run" {
  description = "Keep true until a test notification has been checked in the function logs."
  type        = bool
  default     = true
}

variable "groups" {
  description = "Cloud Identity group emails (create them in the Admin console first). Empty values are skipped."
  type = object({
    org_admins       = optional(string, "")
    sre              = optional(string, "")
    developers       = optional(string, "")
    safety_approvers = optional(string, "")
  })
  default = {}
}

variable "otel" {
  description = "OpenTelemetry pipeline settings. publisher_members are the runtime service accounts of services that run the collector sidecar."
  type = object({
    extra_web_origins         = optional(list(string), [])
    baseline_sampling_percent = optional(number, 20)
    publisher_members         = optional(list(string), [])
    pipeline_alert            = optional(bool, false)
  })
  default = {}
}

variable "github_owner" {
  description = "GitHub owner of the Northcrest repositories that deploy with Workload Identity Federation."
  type        = string
  default     = "duckbill70"
}
