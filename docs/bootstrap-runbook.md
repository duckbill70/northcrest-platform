# Bootstrap runbook

From an empty domain to the first CI apply. Steps 1 to 3 cost nothing and do
not start the trial clock; do them first, then start the trial only when you
are ready to run step 4 onwards.

## 0. Before you start

- `gcloud` and Terraform 1.17.x installed locally.
- A public GitHub repository `northcrest-platform` with this code pushed to
  `main`. Turn on secret scanning and push protection
  (Settings > Code security).

## 1. Identity: Cloud Identity Free on the subdomain

1. Check whether `clearwatertech.co` already has Google Workspace or Cloud
   Identity. If it does, add `lab.clearwatertech.co` as a secondary domain in
   that account instead of creating a new one (a domain can only belong to
   one account).
2. Otherwise sign up for Cloud Identity Free with `lab.clearwatertech.co`
   and verify it with the DNS TXT record Google gives you. This creates the
   Google Cloud **Organization**.
3. Turn on 2-step verification for the super admin. Create a separate
   day-to-day admin user and keep the super admin for break-glass only.
4. Optional now, needed for `iam.tf`: create groups in the Admin console,
   for example `gcp-org-admins@`, `nc-sre@`, `nc-developers@`,
   `nc-safety-approvers@`.
5. **Create the organisation.** Verifying the domain is not always enough,
   and creating a project did not trigger it either. Sign in to
   https://console.cloud.google.com/cloud-setup/organization as the super
   admin and complete only the **Organisation** step. Ignore the other setup
   steps; Terraform does those. The project picker should then list
   `lab.clearwatertech.co` as an organisation.
6. Note the **customer ID** (Admin console > Account > Account settings,
   starts with `C`) for `directory_customer_id`.

## 2. Pick names

- A project prefix that is globally unique, for example `ncair-7f3k`.
  Projects will be `ncair-7f3k-seed`, `ncair-7f3k-customer`, and so on.
- An alert address, for example `alerts@lab.clearwatertech.co`.

## 3. GitHub settings (can be done before the trial)

1. **Environment** `production` (Settings > Environments): add yourself as a
   required reviewer and limit deployment branches to `main`.
2. **Branch protection** on `main`: require a pull request and the status
   check `Format, validate, test, lint`. Add `Plan (org)` once step 6 is done.
3. Push a branch and open a PR: the offline checks should run and pass; the
   plan job is skipped until the repository variables exist.

## 4. Start the Free Trial and gather IDs

1. Sign in to the Cloud console as the day-to-day admin and start the Free
   Trial. Note the billing account **currency**: if it is not GBP, set the
   repository variable `GCP_BILLING_CURRENCY` in step 6 (budgets must use
   the billing account's currency).
2. Make sure your admin user has, at org level, Organization Administrator
   and Project Creator, and Billing Account Administrator on the trial
   billing account.
3. Locally:

   ```
   gcloud auth login
   gcloud auth application-default login
   gcloud organizations list            # ORG ID
   gcloud billing accounts list         # BILLING ACCOUNT ID
   ```

## 5. Apply bootstrap (local, once)

```
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in
terraform init
terraform plan
terraform apply
```

Check the repository's OIDC subject format first:
`gh api repos/<owner>/northcrest-platform/actions/oidc/customization/sub`.
If it shows `"use_immutable_subject": true`, set `platform_repository_id` in
`terraform.tfvars` to the repository's numeric ID (`gh api
repos/<owner>/northcrest-platform --jq .id`). Otherwise the apply job is
refused with `iam.serviceAccounts.getAccessToken` denied, because its token
subject is `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:production`.

Then move its state into the bucket it created:

```
BUCKET=$(terraform output -raw state_bucket)   # read this before backend.tf exists
cp backend.tf.example backend.tf
sed -i.bak "s/REPLACE_WITH_STATE_BUCKET/$BUCKET/" backend.tf && rm backend.tf.bak
terraform init -migrate-state
```

Read the bucket name first. Once `backend.tf` exists, Terraform refuses to run
`terraform output` until you run `init`, so the bucket name comes back empty.

`backend.tf` is git-ignored because it holds your bucket name; keep a copy.

If an API call complains about a missing quota project, run
`gcloud auth application-default set-quota-project <prefix>-seed` and retry.

## 6. Repository variables

`terraform output github_repository_variables` prints most of these. Add
them under Settings > Secrets and variables > Actions > **Variables** (none
are secrets). With the GitHub CLI, from `bootstrap/`:

```
terraform output -json github_repository_variables | \
  jq -r 'to_entries[] | "\(.key)\t\(.value)"' | \
  while IFS=$'\t' read k v; do gh variable set "$k" --body "$v"; done
gh variable set KILL_SWITCH_DRY_RUN --body "true"
gh variable set ALERT_EMAIL --body "<an address you read>"
```

The repo is public and `ALERT_EMAIL` appears in plan comments, so consider
an alias.

| Variable | Example |
|---|---|
| `GCP_WIF_PROVIDER` | `projects/123/locations/global/workloadIdentityPools/github/providers/github-actions` |
| `GCP_TF_PLAN_SA` | `tf-plan@ncair-7f3k-seed.iam.gserviceaccount.com` |
| `GCP_TF_APPLY_SA` | `tf-apply@ncair-7f3k-seed.iam.gserviceaccount.com` |
| `GCP_TF_STATE_BUCKET` | `ncair-7f3k-tfstate` |
| `GCP_SEED_PROJECT` | `ncair-7f3k-seed` |
| `GCP_ORG_ID` | `123456789012` |
| `GCP_BILLING_ACCOUNT` | `XXXXXX-XXXXXX-XXXXXX` |
| `GCP_PROJECT_PREFIX` | `ncair-7f3k` |
| `ALERT_EMAIL` | `alerts@lab.clearwatertech.co` |
| `GCP_DIRECTORY_CUSTOMER_ID` | `C0xxxxxxx` (optional) |
| `GCP_GROUPS` | `{"sre":"nc-sre@lab.clearwatertech.co"}` (optional, JSON) |
| `GCP_BILLING_CURRENCY` | `GBP` (optional, defaults to GBP) |
| `KILL_SWITCH_DRY_RUN` | `true` (leave until step 9) |

## 7. First CI apply

1. Open a PR (any small change, such as a README edit under `org/`). The
   `Plan (org)` job comments the plan: expect 5 folders, 6 projects, org
   policies, budgets and the kill switch.
2. Merge. `Terraform apply` waits for your approval on `production`;
   approve it. The apply only runs on its own for changes under `org/`,
   `modules/` or `.terraform-version`; after a docs-only merge, start it from
   Actions > Terraform apply > Run workflow.
3. If it fails with a billing quota error, see "Linked-project limit" in the
   README.

If the apply fails with "Cloud Resource Manager API has not been used in
project <prefix>-<name>", enable it once on the billed projects, then re-run
the apply:

```
for p in observability platform customer flight-ops; do
  gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
    --project=<prefix>-$p
done
```

Terraform bills each call to the resource's own project, and it needs these
two APIs there to read the project's other APIs.

## 8. Billing export

Console > Billing > Billing export > BigQuery export: turn on **Detailed
usage cost** into project `<prefix>-observability`, dataset `billing_export`.

## 9. Test the kill switch, then arm it

1. Publish a fake over-budget notification:

   ```
   gcloud pubsub topics publish budget-notifications \
     --project=<prefix>-observability \
     --message='{"budgetDisplayName":"test","costAmount":11,"budgetAmount":10,"currencyCode":"GBP"}'
   ```

2. In Logs Explorer for `<prefix>-observability`, filter
   `jsonPayload.component="kill-switch"`. You should see the notification, a
   `detaching billing` line for each non-core project and `"dry_run": true`.
3. Set the repository variable `KILL_SWITCH_DRY_RUN` to `false` and re-run
   the apply workflow.

## Undoing things

- The seed project and workload projects have `deletion_policy = "PREVENT"`
  and folders have deletion protection, so `terraform destroy` stops before
  deleting them. Change those first if you really mean it.
- To restore billing after the kill switch fires:
  `gcloud billing projects link <project> --billing-account=<id>`, then fix
  the cause and re-run apply.
