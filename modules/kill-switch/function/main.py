"""Northcrest Air budget kill switch.

Triggered by Cloud Billing budget notifications on Pub/Sub. Budgets only
warn; this function acts on them:

* spend >= STOP_THRESHOLD of the budget: stop VMs labelled VM_LABEL=stop and
  pause Cloud Scheduler jobs whose names start with SCHEDULER_JOB_PREFIX in
  every TARGET_PROJECTS project (the load generators).
* spend >= DETACH_THRESHOLD: detach billing from every NON_CORE_PROJECTS
  project, which stops all paid resources in them.

With DRY_RUN=true (the default) it only logs what it would do. Every action is
written as a structured log entry so a log-based metric can alert on it.
"""

from __future__ import annotations

import base64
import json
import os
from typing import Any

import functions_framework


def _env_list(name: str) -> list[str]:
    return [p.strip() for p in os.environ.get(name, "").split(",") if p.strip()]


def _config() -> dict[str, Any]:
    return {
        "dry_run": os.environ.get("DRY_RUN", "true").lower() != "false",
        "stop_threshold": float(os.environ.get("STOP_THRESHOLD", "0.9")),
        "detach_threshold": float(os.environ.get("DETACH_THRESHOLD", "1.0")),
        "target_projects": _env_list("TARGET_PROJECTS"),
        "non_core_projects": _env_list("NON_CORE_PROJECTS"),
        "region": os.environ.get("REGION", "us-central1"),
        "vm_label": os.environ.get("VM_LABEL", "kill-switch"),
        "job_prefix": os.environ.get("SCHEDULER_JOB_PREFIX", "loadgen-"),
    }


def log(severity: str, message: str, **fields: Any) -> None:
    """Write one structured log line that Cloud Logging parses as JSON."""
    print(json.dumps({"severity": severity, "message": message,
                      "component": "kill-switch", **fields}), flush=True)


def parse_notification(cloud_event: Any) -> dict[str, Any]:
    raw = cloud_event.data["message"]["data"]
    return json.loads(base64.b64decode(raw).decode("utf-8"))


def decide(notification: dict[str, Any], cfg: dict[str, Any]) -> dict[str, Any]:
    """Pure decision step, kept separate so it can be unit tested."""
    cost = float(notification.get("costAmount", 0.0))
    budget = float(notification.get("budgetAmount", 0.0))
    ratio = cost / budget if budget > 0 else 0.0
    return {
        "ratio": round(ratio, 4),
        "stop_load": budget > 0 and ratio >= cfg["stop_threshold"],
        "detach_billing": budget > 0 and ratio >= cfg["detach_threshold"],
    }


# --- Actions ----------------------------------------------------------------

def stop_vms(project: str, label: str, dry_run: bool) -> None:
    from google.cloud import compute_v1

    client = compute_v1.InstancesClient()
    request = compute_v1.AggregatedListInstancesRequest(
        project=project, filter=f'labels.{label}="stop"')
    for zone, scoped in client.aggregated_list(request=request):
        for inst in scoped.instances or []:
            if inst.status != "RUNNING":
                continue
            zone_name = zone.split("/")[-1]
            log("WARNING", "stopping VM", action="stop_vm", project=project,
                zone=zone_name, instance=inst.name, dry_run=dry_run)
            if not dry_run:
                client.stop(project=project, zone=zone_name, instance=inst.name)


def pause_jobs(project: str, region: str, prefix: str, dry_run: bool) -> None:
    from google.cloud import scheduler_v1

    client = scheduler_v1.CloudSchedulerClient()
    parent = f"projects/{project}/locations/{region}"
    for job in client.list_jobs(parent=parent):
        short = job.name.split("/")[-1]
        if not short.startswith(prefix) or job.state != scheduler_v1.Job.State.ENABLED:
            continue
        log("WARNING", "pausing scheduler job", action="pause_job",
            project=project, job=short, dry_run=dry_run)
        if not dry_run:
            client.pause_job(name=job.name)


def detach_billing(project: str, dry_run: bool) -> None:
    from google.cloud import billing_v1

    client = billing_v1.CloudBillingClient()
    name = f"projects/{project}"
    info = client.get_project_billing_info(name=name)
    if not info.billing_enabled:
        return
    log("CRITICAL", "detaching billing", action="detach_billing",
        project=project, dry_run=dry_run)
    if not dry_run:
        client.update_project_billing_info(
            name=name,
            project_billing_info=billing_v1.ProjectBillingInfo(billing_account_name=""),
        )


_NOTHING_TO_DO = (
    "has not been used in project",  # API off: no VMs or jobs can exist
    "SERVICE_DISABLED",
    "requires billing to be enabled",  # unbilled project: nothing can run
)


def _nothing_to_do(exc: Exception) -> bool:
    text = str(exc)
    return any(marker in text for marker in _NOTHING_TO_DO)


def _each(projects: list[str], fn, *args) -> None:
    """Run an action per project; one failing project must not stop the rest."""
    for project in projects:
        try:
            fn(project, *args)
        except Exception as exc:  # noqa: BLE001
            if _nothing_to_do(exc):
                log("INFO", "skipped, API off or no billing", project=project,
                    action=fn.__name__)
                continue
            log("ERROR", "action failed", project=project,
                action=fn.__name__, error=str(exc))


@functions_framework.cloud_event
def handle_budget(cloud_event: Any) -> None:
    cfg = _config()
    notification = parse_notification(cloud_event)
    decision = decide(notification, cfg)

    log("INFO", "budget notification",
        budget=notification.get("budgetDisplayName"),
        cost=notification.get("costAmount"),
        amount=notification.get("budgetAmount"),
        currency=notification.get("currencyCode"),
        **decision, dry_run=cfg["dry_run"])

    if decision["stop_load"]:
        _each(cfg["target_projects"], stop_vms, cfg["vm_label"], cfg["dry_run"])
        _each(cfg["target_projects"], pause_jobs, cfg["region"],
              cfg["job_prefix"], cfg["dry_run"])

    if decision["detach_billing"]:
        _each(cfg["non_core_projects"], detach_billing, cfg["dry_run"])
