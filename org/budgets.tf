# Budgets only warn. The whole-estate budget also feeds the kill switch.
# All budgets count cost before credits, so they fire during the Free Trial
# too (with credits included the trial would always show zero spend).

module "kill_switch" {
  source = "../modules/kill-switch"

  project_id           = module.project["observability"].project_id
  region               = var.region
  target_project_ids   = local.billed_project_ids
  non_core_project_ids = local.non_core_project_ids
  dry_run              = var.kill_switch_dry_run
}

resource "google_billing_budget" "estate" {
  depends_on = [google_org_policy_policy.observability_allow_budget_publisher]

  billing_account = var.billing_account_id
  display_name    = "Northcrest estate (monthly)"

  budget_filter {
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(var.monthly_budget)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.25, 0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = module.kill_switch.topic_id
    schema_version                   = "1.0"
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = false
  }
}

# Per-folder budgets, so a cost anomaly can be traced to a business unit.
resource "google_billing_budget" "folder" {
  for_each = var.folder_budgets

  billing_account = var.billing_account_id
  display_name    = "Northcrest ${local.business_units[each.key].display} (monthly)"

  budget_filter {
    resource_ancestors     = [google_folder.unit[each.key].name]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(each.value)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }
}
