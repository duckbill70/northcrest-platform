# Organisations created since 2024 come with some "secure by default" org
# policies already set. Adopt the ones we also manage instead of failing with
# 409 POLICY_ALREADY_EXISTS. An import block is a no-op once the resource is
# in state. On an org without these defaults, remove the matching entry.
locals {
  preexisting_org_policies = toset([
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.uniformBucketLevelAccess",
  ])
}

import {
  for_each = local.preexisting_org_policies
  to       = google_org_policy_policy.boolean[each.key]
  id       = "organizations/${var.org_id}/policies/${each.key}"
}
