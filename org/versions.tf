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

  # Org-level APIs (budgets, org policy) need a quota project when called by a
  # service account; bill them to the seed project.
  user_project_override = true
  billing_project       = var.seed_project_id

  default_labels = {
    managed-by = "terraform"
    repo       = "northcrest-platform"
  }
}
