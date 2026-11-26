# northcrest-platform

Terraform for the Google Cloud foundation of **Northcrest Air**, a fictional
airline that Clearwatertech runs to demonstrate monitoring, operations and
change management. Northcrest Air is not a real company; all traffic is
synthetic and the "safety-critical" systems are simulations.

This repository holds the organisation-level platform: folders, projects,
org policies, IAM, budgets with an automatic kill switch, and the GitHub
Actions pipeline that applies it through Workload Identity Federation. Services,
web apps and ops tooling live in `northcrest-services`, `northcrest-web` and
`northcrest-ops`.

> Status: written and tested offline (mocked provider). Nothing has been
> applied yet. Follow [docs/bootstrap-runbook.md](docs/bootstrap-runbook.md)
> to stand it up.

## Layout

```
bootstrap/            Run once, by hand, with your own admin login
  main.tf             Seed project and the APIs Terraform calls through it
  state.tf            Versioned state bucket (us-central1, private)
  wif.tf              GitHub OIDC pool; plan and apply trust rules
  service-accounts.tf tf-plan (read-only) and tf-apply, with org roles
  tests/              terraform test, mocked provider
org/                  Applied by CI on merge to main
  folders.tf          One folder per business unit
  projects.tf         Six projects, data-driven from locals.tf
  org-policies.tf     Org-wide guardrails, stricter flight-ops folder
  iam.tf              Group-based access (optional until groups exist)
  observability.tf    Metrics scope, alert channel, billing export dataset
  budgets.tf          Estate and per-folder budgets, kill switch wiring
  telemetry.tf        OpenTelemetry pipeline in the observability project
  tests/              terraform test, mocked provider
modules/project/      A project: folder, billing, no default network, APIs
modules/kill-switch/  Pub/Sub + Cloud Run function acting on budget alerts
modules/otel-pipeline/ OpenTelemetry agents, edge and gateway collectors
.github/workflows/    PR checks and plan, gated apply, nightly drift check
```

## Hierarchy

```
lab.clearwatertech.co (Organization)
├── <prefix>-seed                    state, WIF, Terraform identities (bootstrap)
├── Customer Channels   (commercial)      <prefix>-customer        core
├── Airport Operations  (operational)     <prefix>-airport-ops
├── Flight Operations   (safety-critical) <prefix>-flight-ops
├── Commercial and Data (internal)        <prefix>-commercial
└── Platform            (shared)          <prefix>-platform        core
                                          <prefix>-observability   core
```

"Core" projects keep billing when the kill switch fires, so the public demo,
monitoring and the switch itself keep working. The other three lose billing.

## How changes flow

| Event | Workflow | Identity | What happens |
|---|---|---|---|
| Pull request | `terraform-pr.yml` | none, then `tf-plan` | fmt, validate, `terraform test`, kill switch unit tests, collector config validation, tflint, Checkov; then a plan posted as a PR comment |
| Merge to `main` | `terraform-apply.yml` | `tf-apply` | Waits for approval on the `production` environment, then plans and applies |
| 05:17 UTC daily | `terraform-drift.yml` | `tf-plan` | Plans against live state and opens or updates a `drift` issue if anything changed outside code |

No Google credentials are stored in GitHub. `tf-plan` can be used by any
workflow in this repository; `tf-apply` only by jobs running in the
`production` environment, which needs a reviewer's approval. Both are bound
to this repository by owner ID, not only by name.

Until bootstrap has run, the plan, apply and drift jobs skip themselves and
only the offline checks run, so the repo can go public before the trial
starts.

## Guardrails

- **Region:** `gcp.resourceLocations` limits everything to `us-central1`, the
  free-tier region. Later phases must create Firestore in `us-central1` (not
  `nam5`), Secret Manager secrets with user-managed replication, and BigQuery
  datasets in `us-central1`.
- **Org policies:** no service account keys, no public buckets, uniform bucket
  access, no default networks, OS Login, no serial ports, private Cloud SQL.
- **Flight operations:** no external VM IPs, and (once `directory_customer_id`
  is set) only Northcrest identities can be granted access, so its APIs can
  never be opened to `allUsers`.
- **Budgets:** £10 a month for the estate (25/50/90/100% plus forecast) and a
  small budget per folder. All budgets count cost **before credits**; with
  credits included the trial would always show zero spend and nothing would
  fire.
- **Kill switch:** the estate budget publishes to Pub/Sub. At 90% the
  function stops VMs labelled `kill-switch=stop` and pauses Scheduler jobs
  named `loadgen-*`; at 100% it detaches billing from the non-core projects.
  It starts in **dry run** and only logs; switch it on with the
  `KILL_SWITCH_DRY_RUN` repository variable after a test (see runbook).

## Telemetry

Every service, browser and host reports through OpenTelemetry: sidecar and
host agents, a public edge collector on Cloud Run for browsers, and one
gateway on the free e2-micro VM that redacts, derives RED metrics, tail
samples and exports to Cloud Trace, Logging and Monitoring. Pub/Sub sits in
between, so no project needs a network path to the gateway and nothing is
lost while it restarts. Design, free-tier budget and runbook:
[docs/opentelemetry.md](docs/opentelemetry.md).

## Testing locally

```
terraform fmt -check -recursive
(cd bootstrap && terraform init -backend=false && terraform test)
(cd org && terraform init -backend=false && terraform test)
(cd modules/otel-pipeline && terraform init -backend=false && terraform test)
modules/otel-pipeline/tests/validate-configs.sh   # downloads otelcol-contrib
python -m pytest modules/kill-switch/function
```

The tests mock the Google provider, so they need no account.

## Known limits and assumptions

- **Linked-project limit:** new billing accounts can link only a small number
  of projects (reports vary from 5 upwards) and a Free Trial account cannot
  ask for more. This layout links 7. If the first apply fails with a billing
  quota error, remove a project from `org/locals.tf` (for example fold
  `airport-ops` into `flight-ops`) and re-apply.
- **Demo windows vs the budget:** GKE and Cloud SQL demo windows will exceed
  £10 gross. Raise `monthly_budget` (or set the kill switch to dry run) for
  those weeks, or the switch will stop them.
- **Billing export** has no API; switch it on once in the console after the
  first apply (runbook step 8).
- Pinned versions: Terraform 1.17.2, Google provider `~> 8.12`. Action and
  tflint plugin versions were not checked against their latest releases;
  Dependabot is configured to keep the actions current, and the tflint Google
  plugin version in `.tflint.hcl` may need a bump.
- Data Access audit logs are off (billable log volume); Admin Activity audit
  logs are always on.
