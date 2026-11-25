# Guardrails for the whole org. Stricter rules for flight operations sit at
# the bottom.

locals {
  org_boolean_constraints = {
    "iam.disableServiceAccountKeyCreation"            = "No service account keys; GitHub uses Workload Identity Federation."
    "iam.automaticIamGrantsForDefaultServiceAccounts" = "Default service accounts get no Editor role."
    "storage.publicAccessPrevention"                  = "No public buckets."
    "storage.uniformBucketLevelAccess"                = "Bucket access through IAM only."
    "compute.skipDefaultNetworkCreation"              = "No default VPC with open firewall rules."
    "compute.requireOsLogin"                          = "SSH through IAM-controlled OS Login."
    "compute.disableSerialPortAccess"                 = "No serial console access."
    "sql.restrictPublicIp"                            = "Cloud SQL demo instances stay private."
  }
}

resource "google_org_policy_policy" "boolean" {
  for_each = local.org_boolean_constraints

  name   = "organizations/${var.org_id}/policies/${each.key}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Keep everything in us-central1, the region where Compute Engine and Cloud
# Storage are free. Consequences for later phases:
# - Firestore must be created in us-central1, not the nam5 multi-region.
# - Secret Manager secrets need user-managed replication in us-central1.
# - BigQuery datasets must use location us-central1, not the US multi-region.
resource "google_org_policy_policy" "resource_locations" {
  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = ["in:${var.region}-locations"]
      }
    }
  }
}

# Flight operations (simulated safety-critical): only identities from the
# Northcrest directory can be granted access, so its APIs can never be made
# public with allUsers, and its VMs get no external IPs.
resource "google_org_policy_policy" "flight_ops_domain_restriction" {
  count = var.directory_customer_id == "" ? 0 : 1

  name   = "${google_folder.unit["flight-operations"].name}/policies/iam.allowedPolicyMemberDomains"
  parent = google_folder.unit["flight-operations"].name

  spec {
    rules {
      values {
        allowed_values = [var.directory_customer_id]
      }
    }
  }
}

resource "google_org_policy_policy" "flight_ops_no_external_ip" {
  name   = "${google_folder.unit["flight-operations"].name}/policies/compute.vmExternalIpAccess"
  parent = google_folder.unit["flight-operations"].name

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}
