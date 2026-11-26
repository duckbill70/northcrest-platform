terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }

  # Partial configuration: CI passes -backend-config="bucket=<state bucket>".
  backend "gcs" {
    prefix = "org"
  }
}

provider "google" {
  region = var.region

  # No quota-project override. Calls on a project's resources are billed and
  # quota-checked against that project, where the module enables the APIs.
  # Org-level calls (folders, org policy, budgets) fall back to the calling
  # service account's own project, the seed, which has those APIs enabled.
  # (billing_project = seed sent every call to the seed, so e.g. Pub/Sub in
  # the observability project failed with SERVICE_DISABLED on the seed.)
  user_project_override = false

  default_labels = {
    managed-by = "terraform"
    repo       = "northcrest-platform"
  }
}
