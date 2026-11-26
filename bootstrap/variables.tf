variable "org_id" {
  description = "Numeric ID of the Google Cloud Organization created by Cloud Identity (gcloud organizations list)."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID in the form XXXXXX-XXXXXX-XXXXXX (the Free Trial account)."
  type        = string
}

variable "project_prefix" {
  description = "Short, globally unique prefix for every project ID, for example \"ncair-7f3k\". Lowercase letters, digits and hyphens, at most 16 characters so <prefix>-observability fits the 30-character project ID limit."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,14}[a-z0-9]$", var.project_prefix))
    error_message = "project_prefix must be 5 to 16 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Default region. us-central1 keeps Cloud Storage and Compute Engine inside the free tier."
  type        = string
  default     = "us-central1"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the Northcrest repositories."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of that owner (https://api.github.com/users/<owner>). Pinning the ID stops a re-registered name from inheriting access."
  type        = string
}

variable "github_repositories" {
  description = "Repositories allowed to exchange GitHub OIDC tokens through the pool at all. Access to each service account is granted separately."
  type        = list(string)
  default     = ["northcrest-platform", "northcrest-services", "northcrest-web", "northcrest-ops"]
}

variable "platform_repository" {
  description = "Repository whose workflows run Terraform plan and apply."
  type        = string
  default     = "northcrest-platform"
}

variable "platform_repository_id" {
  description = "Numeric GitHub ID of the platform repository. Set it when the repository uses immutable OIDC subjects (gh api repos/<owner>/<repo>/actions/oidc/customization/sub shows use_immutable_subject = true); the token subject is then repo:<owner>@<owner_id>/<repo>@<repo_id>:... instead of repo:<owner>/<repo>:..."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.platform_repository_id))
    error_message = "platform_repository_id must be the numeric repository ID, or empty."
  }
}

variable "apply_environment" {
  description = "GitHub Environment that apply jobs must run in. Only jobs in this environment can impersonate the apply service account."
  type        = string
  default     = "production"
}
