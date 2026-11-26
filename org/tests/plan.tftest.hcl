# Offline tests: `terraform test` in org/. The Google provider is mocked, so
# no credentials or cloud account are needed. Runs in CI on every PR.

mock_provider "google" {
  override_during = plan

  mock_resource "google_folder" {
    defaults = {
      name      = "folders/111111111111"
      folder_id = "111111111111"
    }
  }
  mock_resource "google_project" {
    defaults = {
      number = "222222222222"
    }
  }
  mock_resource "google_pubsub_topic" {
    defaults = {
      id = "projects/ncair-test-observability/topics/budget-notifications"
    }
  }
  mock_resource "google_monitoring_notification_channel" {
    defaults = {
      id = "projects/ncair-test-observability/notificationChannels/1"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email  = "sa@ncair-test-observability.iam.gserviceaccount.com"
      member = "serviceAccount:sa@ncair-test-observability.iam.gserviceaccount.com"
      id     = "projects/ncair-test-observability/serviceAccounts/sa@ncair-test-observability.iam.gserviceaccount.com"
    }
  }
}

# imports.tf adopts these; mock providers can't import, so stub them.
override_resource {
  target = google_org_policy_policy.boolean["iam.automaticIamGrantsForDefaultServiceAccounts"]
  values = {
    name = "organizations/123456789012/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  }
}

override_resource {
  target = google_org_policy_policy.boolean["storage.uniformBucketLevelAccess"]
  values = {
    name = "organizations/123456789012/policies/storage.uniformBucketLevelAccess"
  }
}

variables {
  org_id             = "123456789012"
  billing_account_id = "000000-000000-000000"
  seed_project_id    = "ncair-test-seed"
  project_prefix     = "ncair-test"
  alert_email        = "alerts@example.com"
}

run "hierarchy" {
  command = plan

  assert {
    condition     = length(google_folder.unit) == 5
    error_message = "Expected one folder per business unit."
  }

  assert {
    condition     = length(module.project) == 6
    error_message = "Expected six workload projects."
  }

  assert {
    condition     = module.project["flight-ops"].project_id == "ncair-test-flight-ops"
    error_message = "Project IDs must be prefix-key."
  }
}

run "unbilled_projects_fold_into_hosts" {
  command = plan

  assert {
    condition     = !module.project["airport-ops"].billed && !module.project["commercial"].billed && module.project["flight-ops"].billed && module.project["platform"].billed
    error_message = "By default only airport-ops and commercial are unbilled."
  }

  assert {
    condition     = output.workload_projects["airport-ops"] == "ncair-test-customer" && output.workload_projects["commercial"] == "ncair-test-observability" && output.workload_projects["flight-ops"] == "ncair-test-flight-ops"
    error_message = "Unbilled units must deploy to their host project; flight-ops stays on its own."
  }
}

run "all_projects_billed_when_limit_raised" {
  command = plan

  variables {
    unbilled_projects = []
  }

  assert {
    condition     = alltrue([for k, m in module.project : m.billed]) && output.workload_projects["commercial"] == "ncair-test-commercial"
    error_message = "An empty unbilled_projects must bill every project and give each unit its own."
  }
}

run "flight_ops_cannot_be_unbilled" {
  command = plan

  variables {
    unbilled_projects = ["flight-ops"]
  }

  expect_failures = [var.unbilled_projects]
}

run "kill_switch_never_detaches_core_projects" {
  command = plan

  assert {
    condition = (
      toset(local.non_core_project_ids) ==
      toset(["ncair-test-airport-ops", "ncair-test-flight-ops", "ncair-test-commercial"])
    )
    error_message = "Only airport-ops, flight-ops and commercial may lose billing."
  }

  assert {
    condition     = module.kill_switch.topic_id == google_billing_budget.estate.all_updates_rule[0].pubsub_topic
    error_message = "The estate budget must publish to the kill switch topic."
  }
}

run "kill_switch_dry_run_by_default" {
  command = plan

  assert {
    condition     = module.kill_switch.dry_run == true
    error_message = "The kill switch must default to dry run."
  }
}

run "budgets_ignore_credits" {
  command = plan

  assert {
    condition     = google_billing_budget.estate.budget_filter[0].credit_types_treatment == "EXCLUDE_ALL_CREDITS"
    error_message = "Budgets must count spend before credits so they work during the trial."
  }

  assert {
    condition     = length(google_billing_budget.folder) == 5
    error_message = "Expected one budget per folder."
  }
}

run "region_locked" {
  command = plan

  assert {
    condition     = google_org_policy_policy.resource_locations.spec[0].rules[0].values[0].allowed_values == tolist(["in:us-central1-locations"])
    error_message = "Resources must be restricted to us-central1."
  }
}

run "domain_restriction_only_with_customer_id" {
  command = plan

  variables {
    directory_customer_id = "C0abc1234"
  }

  assert {
    condition     = length(google_org_policy_policy.flight_ops_domain_restriction) == 1
    error_message = "Flight operations must get domain-restricted sharing when a customer ID is set."
  }
}

run "groups_are_optional" {
  command = plan

  variables {
    groups = { sre = "sre@example.com" }
  }

  assert {
    condition     = length(google_organization_iam_member.group) == 4 && length(google_folder_iam_member.group) == 0
    error_message = "Only the SRE org roles should be bound when only the SRE group is set."
  }
}

run "otel_pipeline_in_observability_project" {
  command = plan

  assert {
    condition     = module.otel.topics["traces"] != null && length(module.otel.topics) == 3
    error_message = "The OpenTelemetry pipeline must be deployed with one topic per signal."
  }

  assert {
    condition     = contains(local.projects["observability"].services, "telemetry.googleapis.com")
    error_message = "The observability project needs the Telemetry API for OTLP export."
  }
}

run "rejects_prefix_that_overruns_project_ids" {
  command = plan

  variables {
    project_prefix = "ncair-abcdefghijk" # 17 chars + "-observability" = 31
  }

  expect_failures = [var.project_prefix]
}
