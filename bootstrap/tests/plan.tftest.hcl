# Offline tests: `terraform test` in bootstrap/. Google provider mocked.

mock_provider "google" {
  override_during = plan

  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/github"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/ncair-test-seed/serviceAccounts/sa@ncair-test-seed.iam.gserviceaccount.com"
      email  = "sa@ncair-test-seed.iam.gserviceaccount.com"
      member = "serviceAccount:sa@ncair-test-seed.iam.gserviceaccount.com"
    }
  }
}

variables {
  org_id             = "123456789012"
  billing_account_id = "000000-000000-000000"
  project_prefix     = "ncair-test"
  github_owner       = "example-owner"
  github_owner_id    = "42"
}

run "wif_is_locked_to_owner_and_repos" {
  command = plan

  assert {
    condition = google_iam_workload_identity_pool_provider.github.attribute_condition == join("", [
      "assertion.repository_owner_id == '42' && assertion.repository in [",
      "'example-owner/northcrest-platform', 'example-owner/northcrest-services', ",
      "'example-owner/northcrest-web', 'example-owner/northcrest-ops']",
    ])
    error_message = "Unexpected WIF attribute condition."
  }
}

run "apply_only_from_protected_environment" {
  command = plan

  assert {
    condition     = google_service_account_iam_member.apply_wif.member == "principal://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/github/subject/repo:example-owner/northcrest-platform:environment:production"
    error_message = "Apply must be limited to the production environment of the platform repo."
  }

  assert {
    condition     = startswith(google_service_account_iam_member.plan_wif.member, "principalSet://")
    error_message = "Plan should be available to any workflow in the platform repo."
  }
}

run "apply_subject_with_immutable_ids" {
  command = plan

  variables {
    platform_repository_id = "1472024379"
  }

  assert {
    condition     = google_service_account_iam_member.apply_wif.member == "principal://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/github/subject/repo:example-owner@42/northcrest-platform@1472024379:environment:production"
    error_message = "With a repository ID, the apply subject must use GitHub's immutable form."
  }
}

run "state_bucket_is_private_and_versioned" {
  command = plan

  assert {
    condition     = google_storage_bucket.tfstate.versioning[0].enabled && google_storage_bucket.tfstate.public_access_prevention == "enforced"
    error_message = "State bucket must be versioned and never public."
  }
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    project_prefix = "Bad_Prefix"
  }

  expect_failures = [var.project_prefix]
}

run "rejects_prefix_that_overruns_project_ids" {
  command = plan

  variables {
    project_prefix = "ncair-abcdefghijk" # 17 characters
  }

  expect_failures = [var.project_prefix]
}
