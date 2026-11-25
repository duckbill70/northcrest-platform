terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
  }

  # Bootstrap starts with local state. After the first apply, copy
  # backend.tf.example to backend.tf and run `terraform init -migrate-state`
  # to move this state into the bucket it has just created.
}

provider "google" {
  region = var.region
}
