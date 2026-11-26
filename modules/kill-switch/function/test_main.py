"""Unit tests for the decision logic: python -m pytest modules/kill-switch/function"""

import base64
import json
from types import SimpleNamespace

import main

CFG = {"stop_threshold": 0.9, "detach_threshold": 1.0}


def event(payload):
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    return SimpleNamespace(data={"message": {"data": data}})


def test_below_thresholds_does_nothing():
    d = main.decide({"costAmount": 5, "budgetAmount": 10}, CFG)
    assert d == {"ratio": 0.5, "stop_load": False, "detach_billing": False}


def test_stop_threshold_stops_load_only():
    d = main.decide({"costAmount": 9.2, "budgetAmount": 10}, CFG)
    assert d["stop_load"] and not d["detach_billing"]


def test_over_budget_detaches():
    d = main.decide({"costAmount": 10.01, "budgetAmount": 10}, CFG)
    assert d["stop_load"] and d["detach_billing"]


def test_zero_budget_is_ignored():
    d = main.decide({"costAmount": 3, "budgetAmount": 0}, CFG)
    assert not d["stop_load"] and not d["detach_billing"]


def test_parse_notification_roundtrip():
    payload = {"costAmount": 1.5, "budgetAmount": 10, "budgetDisplayName": "x"}
    assert main.parse_notification(event(payload)) == payload


def test_dry_run_is_default(monkeypatch):
    monkeypatch.delenv("DRY_RUN", raising=False)
    assert main._config()["dry_run"] is True


def test_handler_runs_both_stages_in_dry_run(monkeypatch):
    calls = []
    monkeypatch.delenv("DRY_RUN", raising=False)
    monkeypatch.setenv("TARGET_PROJECTS", "p1")
    monkeypatch.setenv("NON_CORE_PROJECTS", "p2")
    monkeypatch.setattr(main, "stop_vms", lambda *a: calls.append(("stop", a)))
    monkeypatch.setattr(main, "pause_jobs", lambda *a: calls.append(("pause", a)))
    monkeypatch.setattr(main, "detach_billing", lambda *a: calls.append(("detach", a)))
    main.handle_budget(event({"costAmount": 12, "budgetAmount": 10}))
    kinds = [c[0] for c in calls]
    assert kinds == ["stop", "pause", "detach"]
    # dry_run flag (last arg) is passed through as True
    assert all(c[1][-1] is True for c in calls)


def test_disabled_api_is_skipped_not_an_error(capsys):
    def fails(project):
        raise RuntimeError(
            "403 Cloud Scheduler API has not been used in project p1 before")
    main._each(["p1"], fails)
    entry = json.loads(capsys.readouterr().out)
    assert entry["severity"] == "INFO" and entry["action"] == "fails"


def test_other_failures_are_errors(capsys):
    def fails(project):
        raise RuntimeError("403 Permission denied on resource")
    main._each(["p1"], fails)
    entry = json.loads(capsys.readouterr().out)
    assert entry["severity"] == "ERROR"
