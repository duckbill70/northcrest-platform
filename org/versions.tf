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

  # Bill and quota-check each call against the resource's own project, where
  # modules/project enables the APIs. Without this, Pub/Sub, BigQuery and
  # others charge the credentials' project (the seed) and fail with
  # SERVICE_DISABLED there. No billing_project: that would send every call to
  # the seed. Project-less calls (folders, org policy, budgets) still use the
  # seed. Needs serviceusage.services.use on each project (bootstrap grants
  # serviceUsageConsumer at org level to both Terraform accounts).
  user_project_override = true

  default_labels = {
    managed-by = "terraform"
    repo       = "northcrest-platform"
  }
}
