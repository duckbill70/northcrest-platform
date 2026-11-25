# OpenTelemetry at Northcrest Air

How telemetry gets from Northcrest services, browsers and hosts into Google
Cloud Observability, built only from OpenTelemetry components and kept
inside the free tier. Code: [`modules/otel-pipeline`](../modules/otel-pipeline),
wired in [`org/telemetry.tf`](../org/telemetry.tf).

## Topology

```
 Workload projects                     Observability project
 ─────────────────                     ─────────────────────────────────────────────
 Cloud Run service                     Pub/Sub                  e2-micro VM (free tier)
 ┌─────────┬─────────┐  OTLP over      ┌────────────┐           ┌───────────────────────┐
 │  app    │ sidecar │─ Pub/Sub ──────▶│ otel-traces│──┐        │ host agent            │
 │ (SDK)   │ agent   │  (publish only) │ otel-metrics│ ├─ pull ─▶│  hostmetrics, logs,   │
 └─────────┴─────────┘                 │ otel-logs  │──┘        │  local OTLP (k6)      │
                                       └────────────┘           │        │ loopback     │
 Browsers (React RUM),                       ▲                  │        ▼              │
 Playwright synthetics                       │                  │ gateway               │
        │ OTLP/HTTP + CORS            ┌──────┴──────┐           │  redact, pseudonymise │
        └────────────────────────────▶│ edge        │           │  span metrics (RED)   │
                                      │ collector   │           │  tail sampling        │
                                      │ (Cloud Run) │           │  metric allowlist     │
                                      └─────────────┘           └───────┬───────────────┘
                                                                        │
                                   traces, logs: OTLP to telemetry.googleapis.com
                                   metrics: googlecloud exporter (workload.googleapis.com)
                                                                        ▼
                                        Cloud Trace · Cloud Logging · Cloud Monitoring
```

Four collector roles, all the same Google-Built OpenTelemetry Collector image
with a different config:

| Role | Where | Config | Job |
|---|---|---|---|
| **Sidecar agent** | Next to each service (Cloud Run sidecar or VM) | [`sidecar.yaml`](../modules/otel-pipeline/config/sidecar.yaml) | Receives OTLP on localhost, adds GCP resource identity and Northcrest ownership labels (`northcrest.business_unit`, `northcrest.tier`), publishes to Pub/Sub |
| **Host agent** | Gateway VM | [`agent.yaml`](../modules/otel-pipeline/config/agent.yaml) | Host metrics, container logs, local OTLP for tools such as k6 |
| **Edge collector** | Cloud Run, public | [`edge.yaml`](../modules/otel-pipeline/config/edge.yaml) | Browser and synthetic telemetry: CORS, size limits, drops anything not from a `northcrest-*` service, strips client addresses |
| **Gateway** | Gateway VM | [`gateway.yaml`](../modules/otel-pipeline/config/gateway.yaml) | The single policy point: redaction, pseudonymisation, span metrics, tail sampling, metric allowlist, export |

## Decisions

**Agent plus gateway, not agents straight to Google.** Agents stay dumb and
identical; every rule that matters (what is kept, what is masked, what is
paid for) lives in one reviewed file. That is the pattern large
organisations use, and it is what the demo is meant to show.

**Pub/Sub between them, not a network path.** Six projects, no Shared VPC.
Publishing to a topic needs one IAM grant and no networking, works the same
from any project, and buffers telemetry for 24 hours. Stopping or replacing
the gateway loses nothing: the backlog shows on the dashboard and drains
when it comes back. One topic per signal so a traces backlog cannot hide a
logs backlog.

**Gateway on the free e2-micro VM, not Cloud Run.** Tail sampling holds
traces for 15 seconds before deciding, and span metrics flush every two
minutes. Both need CPU between requests. Cloud Run's request-based billing
throttles CPU outside requests; keeping CPU allocated needs a whole vCPU
around the clock, roughly 2.6 million vCPU-seconds a month against 240,000
free. The VM is free and always on. It has no external IP and no Cloud NAT
(NAT is billed hourly); Private Google Access reaches Pub/Sub, the Telemetry
API, Cloud Monitoring and Artifact Registry.

**Edge on Cloud Run, stateless.** Browsers need a public HTTPS endpoint that
scales to zero. No batch processor and no sending queue, so each request is
published before the response goes back and nothing is left waiting for CPU
that Cloud Run will not give.

**Tail sampling policy.** Kept every time: errors, traces over 2 seconds,
anything from the `safety-critical` tier (flight operations), and anything
carrying `northcrest.fault.scenario` (the fault-injection scenarios).
Everything else: `baseline_sampling_percent` (20% by default).

**Span metrics before sampling.** Request rate, errors and duration come
from 100% of server and consumer spans, so dashboards and SLOs stay exact
while only a fraction of traces is stored.

**Metrics through the `googlecloud` exporter, traces and logs through the
Telemetry API.** OTLP metrics sent to `telemetry.googleapis.com` are billed
per sample with no free tier. `workload.googleapis.com` metrics are billed
by bytes with 150 MiB free per billing account.

## Staying in the free tier

| Service | Free allowance | Expected use |
|---|---|---|
| Compute Engine | 1 e2-micro, 30 GB standard disk, us-central1 | The gateway VM, 10 GB disk. The only free VM on the billing account: k6 shares it. |
| Pub/Sub | 10 GiB a month | Well under 1 GiB: OTLP protobuf, gzip, 200 items per message |
| Cloud Run | 180,000 vCPU-s, 2 million requests | Edge only; scales to zero, at most 2 instances |
| Cloud Trace | 2.5 million spans a month | After tail sampling |
| Cloud Monitoring (bytes) | 150 MiB a month | About 80 MiB: host metrics ≈ 9, RED metrics ≈ 57, collector self-metrics ≈ 14 |
| Cloud Logging | 50 GiB per project | Container logs from the VM plus service logs |
| Dashboards | Free | One pipeline dashboard |
| Alert policies | Billed per condition | Off by default (`otel.pipeline_alert`) |

The biggest risk is metric cardinality. RED metrics are one series per
service, tier and status code, not per route: per-route series for 15
services with 8 routes each would be about 430 MiB a month on their own. The gateway only
exports metrics on its allowlist (`filter/metric_allowlist` in
`gateway.yaml`), so a new metric needs a pull request, and the pull request
is where its cost is discussed.

## What it shows off

1. **Lossless gateway restart.** Stop `otel-gateway`, watch the Pub/Sub
   backlog grow on the *OpenTelemetry pipeline* dashboard, start it, watch
   it drain. Same story for a config change, which replaces the VM.
2. **Risk-tiered sampling.** Flight operations traces are all there;
   commercial traces are sampled; every error from either is there.
3. **Fault injection is never sampled away.** Turn on a fault scenario and
   every affected trace is kept.
4. **Privacy controls in the pipeline.** Send a span with an email address
   or card number in an attribute: it arrives masked. Passenger and crew IDs
   arrive as SHA-256 hashes, still joinable.
5. **Cost governance.** Emit a high-cardinality metric: it never reaches
   Cloud Monitoring.
6. **Four deployment patterns** (sidecar, host agent, edge, gateway) from one
   image, all in code.

## Operating it

SSH (members of the SRE group, through IAP and OS Login):

```
gcloud compute ssh otel-gateway --project <prefix>-observability \
  --zone us-central1-a --tunnel-through-iap
sudo journalctl -u otel-gateway -f     # or -u otel-agent
docker logs otel-gateway
```

Smoke test after the first apply. An error span is always kept, so it
should appear in Trace Explorer in the observability project within a
minute:

```
EDGE=$(terraform -chdir=org output -raw otel_edge_url)
now=$(date +%s%N)
curl -sS -X POST "$EDGE/v1/traces" -H 'Content-Type: application/json' -d '{
  "resourceSpans": [{
    "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "northcrest-smoke-test"}}]},
    "scopeSpans": [{"spans": [{
      "traceId": "'$(openssl rand -hex 16)'", "spanId": "'$(openssl rand -hex 8)'",
      "name": "smoke-test", "kind": 2,
      "startTimeUnixNano": "'$((now - 250000000))'", "endTimeUnixNano": "'$now'",
      "status": {"code": 2, "message": "smoke test"}
    }]}]
  }]
}'
```

Changing a collector config: edit the YAML under
`modules/otel-pipeline/config`, open a pull request (CI runs
`otelcol-contrib validate` on every config), merge. The apply replaces the
VM; Pub/Sub holds telemetry for the minute or two it takes to boot. Host
metrics for that gap are lost.

Adding a service: give its runtime service account publish rights through
`otel.publisher_members` (repository variable `OTEL_SETTINGS`, JSON), deploy
it with the collector sidecar using the `sidecar_config` output, and set
`OTEL_PIPELINE_PROJECT`, `NORTHCREST_BUSINESS_UNIT` and `NORTHCREST_TIER`.
On Cloud Run with request-based billing the sidecar only gets CPU during
requests, so its 2-second batches are sent on the next request; services
with sparse traffic should use a shorter batch timeout or instance-based
billing.

## Limits and next steps

- **One gateway.** Tail sampling needs every span of a trace in one place.
  Scaling out means a load-balancing tier keyed by trace ID (the
  `loadbalancing` exporter) in front of several gateways, which is beyond
  one free VM.
- **Public edge.** Anyone can post to it. CORS only stops browsers; the
  filter, the 1 MiB limit, two instances and the budget kill switch bound
  the damage.
- **Second backend.** Exporting to a second, non-Google backend at the same
  time (to show vendor neutrality) needs internet egress from the VM, so
  Cloud NAT, roughly $1 a month plus data.
- **Unverified until applied.** The configs are checked by
  `otelcol-contrib validate` in CI, not run against real Google APIs. The
  collector image tag and the `roles/telemetry.tracesWriter` role come from
  Google's documentation as of November 2026.
