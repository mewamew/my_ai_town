"""Import external tool reports into the shared Phase 2 evidence store."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

from game.test_bridge.evidence_store import EvidenceStore  # pylint: disable=import-error


DEFAULT_EVIDENCE_ROOT = Path(__file__).resolve().parent / "artifacts"


def _response_json(execution: dict[str, Any]) -> dict[str, Any]:
    """Decode Newman's serialized response body when it contains JSON."""
    response = execution.get("response") or {}
    stream = response.get("stream")
    raw: bytes | None = None
    if isinstance(stream, dict) and isinstance(stream.get("data"), list):
        try:
            raw = bytes(stream["data"])
        except (TypeError, ValueError):
            return {}
    elif isinstance(stream, str):
        raw = stream.encode("utf-8")
    if raw is None:
        return {}
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def import_newman_report(  # pylint: disable=too-many-locals
    report_path: Path,
    evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
) -> str:
    """Import requests and assertions from one Newman JSON report."""
    report = json.loads(report_path.read_text(encoding="utf-8"))
    run = report.get("run") or {}
    executions = run.get("executions") or []
    store = EvidenceStore(
        evidence_root,
        "newman",
        metadata={"report": str(report_path.resolve()), "unit": "assertion"},
    )
    passed = 0
    failed = 0

    for execution in executions:
        item = execution.get("item") or {}
        response = execution.get("response") or {}
        item_name = str(item.get("name") or "unnamed request")
        assertions = execution.get("assertions") or []
        body = _response_json(execution)
        data = body.get("data") if isinstance(body.get("data"), dict) else {}
        request_failed = bool(execution.get("requestError")) or any(
            assertion.get("error") for assertion in assertions
        )
        store.record(
            "http_request",
            name=item_name,
            status="failed" if request_failed else "passed",
            duration_ms=response.get("responseTime"),
            error_type="newman_request_error" if execution.get("requestError") else None,
            message=str(execution.get("requestError") or "") or None,
            request_id=body.get("requestId"),
            session_id=data.get("sessionId"),
            world_generation=data.get("worldGeneration"),
            state_version=data.get("stateVersion"),
            details={"httpStatus": response.get("code")},
        )
        for assertion in assertions:
            error = assertion.get("error")
            status = "failed" if error else "passed"
            passed += int(status == "passed")
            failed += int(status == "failed")
            store.record(
                "assertion",
                name=str(assertion.get("assertion") or "unnamed assertion"),
                status=status,
                error_type=(error or {}).get("name") if isinstance(error, dict) else None,
                message=(error or {}).get("message") if isinstance(error, dict) else None,
                request_id=body.get("requestId"),
                session_id=data.get("sessionId"),
                world_generation=data.get("worldGeneration"),
                state_version=data.get("stateVersion"),
                details={"request": item_name},
            )

    timings = run.get("timings") or {}
    started = float(timings.get("started") or 0)
    completed = float(timings.get("completed") or started)
    store.finish(
        status="passed" if failed == 0 else "failed",
        total=passed + failed,
        passed=passed,
        failed=failed,
        skipped=0,
        other=0,
        duration_ms=max(0.0, completed - started),
    )
    return store.run_id


def _integer(row: dict[str, str], key: str) -> int:
    value = row.get(key, "0").strip()
    return int(float(value or 0))


def _number(row: dict[str, str], key: str) -> float:
    value = row.get(key, "0").strip()
    return float(value or 0)


def _read_csv(path: Path | None) -> list[dict[str, str]]:
    if path is None or not path.is_file():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def import_locust_report(
    stats_path: Path,
    failures_path: Path | None = None,
    exceptions_path: Path | None = None,
    evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
) -> str:
    """Import Locust aggregate CSVs without calling the service again."""
    stats = _read_csv(stats_path)
    failures = _read_csv(failures_path)
    exceptions = _read_csv(exceptions_path)
    aggregate = next((row for row in stats if row.get("Name") == "Aggregated"), None)
    if aggregate is None:
        raise ValueError("Locust stats report does not contain an Aggregated row")

    store = EvidenceStore(
        evidence_root,
        "locust",
        metadata={
            "report": str(stats_path.resolve()),
            "unit": "request",
            "source": "csv_periodic",
        },
    )
    for row in stats:
        name = row.get("Name") or "unnamed endpoint"
        request_count = _integer(row, "Request Count")
        failure_count = _integer(row, "Failure Count")
        store.record(
            "load_metric",
            name=name,
            status="failed" if failure_count else "passed",
            duration_ms=_number(row, "Average Response Time"),
            details={
                "method": row.get("Type") or None,
                "requests": request_count,
                "failures": failure_count,
                "requestsPerSecond": _number(row, "Requests/s"),
                "p50Ms": _number(row, "50%"),
                "p95Ms": _number(row, "95%"),
                "p99Ms": _number(row, "99%"),
                "maxMs": _number(row, "Max Response Time"),
            },
        )
    for row in failures:
        store.record(
            "load_error",
            name=row.get("Name") or "unnamed endpoint",
            status="failed",
            error_type="locust_request_failure",
            message=row.get("Error") or None,
            details={"occurrences": _integer(row, "Occurrences")},
        )
    for row in exceptions:
        store.record(
            "load_error",
            name="locust worker exception",
            status="failed",
            error_type="locust_worker_exception",
            message=row.get("Message") or row.get("Traceback") or None,
            details={"occurrences": _integer(row, "Count")},
        )

    total = _integer(aggregate, "Request Count")
    failed = _integer(aggregate, "Failure Count")
    store.finish(
        status="passed" if failed == 0 and not exceptions else "failed",
        total=total,
        passed=max(0, total - failed),
        failed=failed,
        skipped=0,
        other=0,
        duration_ms=0.0,
    )
    return store.run_id


def import_locust_final_json(
    report_path: Path,
    evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
) -> str:
    """Import the exact final Locust snapshot emitted by the test file."""
    report = json.loads(report_path.read_text(encoding="utf-8"))
    stats = report.get("stats") or []
    failures = report.get("failures") or []
    exceptions = report.get("exceptions") or []
    business_outcomes = report.get("businessOutcomes") or {}
    aggregate = next((row for row in stats if row.get("name") == "Aggregated"), None)
    if aggregate is None:
        raise ValueError("Locust final report does not contain an Aggregated row")

    store = EvidenceStore(
        evidence_root,
        "locust",
        metadata={
            "report": str(report_path.resolve()),
            "unit": "request",
            "users": report.get("users"),
            "scenario": report.get("scenario") or "unspecified",
            "source": "final_event",
        },
    )
    for row in stats:
        failure_count = int(row.get("num_failures") or 0)
        store.record(
            "load_metric",
            name=str(row.get("name") or "unnamed endpoint"),
            status="failed" if failure_count else "passed",
            duration_ms=float(row.get("avg_response_time") or 0),
            details={
                "method": row.get("method"),
                "requests": int(row.get("num_requests") or 0),
                "failures": failure_count,
                "requestsPerSecond": float(row.get("total_rps") or 0),
                "p50Ms": float(
                    row.get("response_time_percentile_0.5")
                    or row.get("median_response_time")
                    or 0
                ),
                "p95Ms": float(row.get("response_time_percentile_0.95") or 0),
                "p99Ms": float(row.get("response_time_percentile_0.99") or 0),
                "maxMs": float(row.get("max_response_time") or 0),
            },
        )
    for row in failures:
        store.record(
            "load_error",
            name=str(row.get("name") or "unnamed endpoint"),
            status="failed",
            error_type="locust_request_failure",
            message=row.get("error"),
            details={"occurrences": int(row.get("occurrences") or 0)},
        )
    for row in exceptions:
        store.record(
            "load_error",
            name="locust worker exception",
            status="failed",
            error_type="locust_worker_exception",
            message=row.get("message") or row.get("traceback"),
            details={"occurrences": int(row.get("count") or 0)},
        )
    for name, count in sorted(business_outcomes.items()):
        store.record(
            "business_outcome",
            name=str(name),
            status="passed",
            details={"count": int(count or 0)},
        )

    total = int(aggregate.get("num_requests") or 0)
    failed = int(aggregate.get("num_failures") or 0)
    store.finish(
        status="passed" if failed == 0 and not exceptions else "failed",
        total=total,
        passed=max(0, total - failed),
        failed=failed,
        skipped=0,
        other=0,
        duration_ms=float(report.get("durationMs") or 0),
    )
    return store.run_id


def import_ci_summary(
    report_path: Path,
    evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
    source: str = "ci",
) -> str:
    """Import one provider-neutral CI stage summary into normalized evidence."""

    report = json.loads(report_path.read_text(encoding="utf-8"))
    stages = report.get("stages") or []
    if not isinstance(stages, list) or not stages:
        raise ValueError("CI summary does not contain any stages")

    store = EvidenceStore(
        evidence_root,
        source,
        metadata={
            "report": str(report_path.resolve()),
            "unit": "stage",
            "ciRunId": report.get("runId"),
            "buildNumber": report.get("buildNumber"),
            "executionMode": report.get("executionMode") or "unknown",
            "sourceFingerprint": report.get("sourceFingerprint"),
            "toolVersions": report.get("toolVersions") or {},
            "disk": report.get("disk") or {},
        },
    )
    counts = {"passed": 0, "failed": 0, "skipped": 0, "other": 0}
    for stage in stages:
        status = str(stage.get("status") or "other").lower()
        normalized = status if status in counts else "other"
        counts[normalized] += 1
        store.record(
            "ci_stage",
            name=str(stage.get("name") or "unnamed stage"),
            status=normalized,
            duration_ms=float(stage.get("durationMs") or 0),
            error_type=stage.get("errorType"),
            message=stage.get("message"),
            details={
                "exitCode": stage.get("exitCode"),
                "reportPaths": stage.get("reportPaths") or [],
            },
        )

    expected_status = str(report.get("status") or "failed").lower()
    final_status = (
        "passed"
        if expected_status == "passed" and counts["failed"] == 0
        else "failed"
    )
    store.finish(
        status=final_status,
        total=len(stages),
        passed=counts["passed"],
        failed=counts["failed"],
        skipped=counts["skipped"],
        other=counts["other"],
        duration_ms=float(report.get("durationMs") or 0),
    )
    return store.run_id


def import_jenkins_summary(
    report_path: Path,
    evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
) -> str:
    """Keep historical Jenkins evidence readable after migrating to Actions."""
    return import_ci_summary(report_path, evidence_root, source="jenkins")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--evidence-root",
        type=Path,
        default=DEFAULT_EVIDENCE_ROOT,
        help="Destination containing JSONL files and phase2_evidence.sqlite3.",
    )
    subparsers = parser.add_subparsers(dest="tool", required=True)
    newman = subparsers.add_parser("newman")
    newman.add_argument("--report", type=Path, required=True)
    locust = subparsers.add_parser("locust")
    source = locust.add_mutually_exclusive_group(required=True)
    source.add_argument("--final-json", type=Path)
    source.add_argument("--stats", type=Path)
    locust.add_argument("--failures", type=Path)
    locust.add_argument("--exceptions", type=Path)
    jenkins = subparsers.add_parser("jenkins")
    jenkins.add_argument("--summary", type=Path, required=True)
    ci_parser = subparsers.add_parser("ci")
    ci_parser.add_argument("--summary", type=Path, required=True)
    return parser


def main() -> int:
    """Import the selected external report and print its shared run ID."""
    args = _parser().parse_args()
    if args.tool == "newman":
        run_id = import_newman_report(args.report, args.evidence_root)
    elif args.tool == "jenkins":
        run_id = import_jenkins_summary(args.summary, args.evidence_root)
    elif args.tool == "ci":
        run_id = import_ci_summary(args.summary, args.evidence_root)
    elif args.final_json:
        run_id = import_locust_final_json(args.final_json, args.evidence_root)
    else:
        run_id = import_locust_report(
            args.stats,
            args.failures,
            args.exceptions,
            args.evidence_root,
        )
    print(f"EVIDENCE_IMPORTED runId={run_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
