"""Shared pytest fixtures for the isolated GameTestBridge process."""

from __future__ import annotations

import collections
import hashlib
import json
import shutil
import socket
import subprocess
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable, Iterator
from urllib.parse import urlsplit

import pytest
import requests
from jsonschema import Draft202012Validator, FormatChecker

from game.test_bridge.evidence_store import (  # pylint: disable=import-error
    BridgeEventStream, EvidenceStore, new_run_id,
)


DEFAULT_BRIDGE_URL = "http://127.0.0.1:18865"
DEFAULT_GODOT_BIN = Path(r"D:\Godot\Godot_v4.7.2-stable_win64_console.exe")
DEFAULT_EVIDENCE_ROOT = Path(__file__).resolve().parents[1] / "artifacts"
_EVIDENCE_CONTEXT: dict[str, Any] = {
    "store": None,
    "started_at": 0.0,
    "cases": {},
    "bridge_processes": {},
}


def _audit_event_window(before: dict, after: dict, events: list[dict]) -> dict:
    """Audit a bounded emitted sequence window, never delivery or historical replay."""
    start, end = before["lastEmittedEventSequence"], after["lastEmittedEventSequence"]
    result = {"beforeCursor": before, "afterCursor": after, "allFramesComplete": None,
              "scope": "bounded emitted-event observation window; NOT delivery guarantee"}
    if before["streamId"] != after["streamId"] or end < start or end - start > 4096:
        result["completenessBlindSpot"] = "different stream, regressed cursor or window over 4096"
        return result
    expected = list(range(int(start) + 1, int(end) + 1))
    sequences = [event["eventSequence"] for event in events]
    foreign = [event["eventId"] for event in events
               if event["eventId"] != f'{before["streamId"]}-event-{int(event["eventSequence"])}']
    missing = sorted(set(expected) - set(sequences))
    ordered = all(current > previous for previous, current in zip(sequences, sequences[1:]))
    result.update(expectedEventCount=len(expected), observedEventCount=len(events),
                  missingEventSequences=missing, foreignEventIds=foreign,
                  unexpectedEventSequences=sorted(set(sequences) - set(expected)),
                  strictlyIncreasing=ordered, worldGenerationChanged=(
                      before["worldGeneration"] != after["worldGeneration"]),
                  allFramesComplete=(sequences == expected and not foreign),
                  completenessBlindSpot=None)
    return result


@pytest.fixture(name="event_window_audit")
def fixture_event_window_audit() -> Callable[[dict, dict, list[dict]], dict]:
    """Expose the same window audit to Python and real Godot wire evidence tests."""
    return _audit_event_window


@pytest.fixture(name="cursor_replay_evidence")
def fixture_cursor_replay_evidence() -> Callable:
    """Record controlled consumption of actual Godot events with real HTTP cursors."""
    def record(evidence, events, observations, cursors):
        windows = []
        for scenario, indexes in {"complete-generation-window": [2, 3, 4],
                                  "omitted-first-commandless": [3, 4],
                                  "omitted-last-commandless": [2, 3],
                                  "omitted-all": []}.items():
            replay_ids = []
            for index in indexes:
                source = observations[index]
                replay = evidence.record("controlled_event_replay", name=events[index]["eventType"],
                    event_sequence=events[index]["eventSequence"], details={
                        **source["details"], "observationSource": "controlled-replay",
                        "sourceEvidenceId": source["eventId"], "replayScenario": scenario})
                replay_ids.append(replay["eventId"])
            window = _audit_event_window(cursors["oldCursor"], cursors["finalCursor"],
                                        [events[index] for index in indexes])
            evidence.record("cursor_window_checkpoint", name=scenario, status="observed",
                            details={"eventWindow": window, "replayEvidenceIds": replay_ids,
                                     "sourceExperimentEvidenceId": cursors["experimentEvidenceId"],
                                     "factsSource": "actual driver HTTP cursor responses"})
            windows.append(window)
        changed = _audit_event_window(cursors["finalCursor"], cursors["replacementCursor"], [])
        evidence.record("cursor_window_checkpoint", name="actual-bridge-replacement",
                        status="observed", details={**changed,
                            "sourceExperimentEvidenceId": cursors["experimentEvidenceId"]})
        return windows, changed
    return record


def pytest_addoption(parser: pytest.Parser) -> None:
    """Register bridge location and isolated-process command-line options."""
    group = parser.getgroup("gametest-bridge")
    group.addoption(
        "--bridge-url",
        dest="bridge_url",
        default=DEFAULT_BRIDGE_URL,
        help="Base URL for the isolated GameTestBridge fixture.",
    )
    group.addoption(
        "--external-bridge",
        dest="external_bridge",
        action="store_true",
        default=False,
        help="Use an already-running bridge instead of starting the isolated Godot fixture.",
    )
    group.addoption(
        "--godot-bin",
        dest="godot_bin",
        default="",
        help="Path to the Godot console executable used to start the isolated fixture.",
    )
    group.addoption(
        "--evidence-root",
        dest="evidence_root",
        default=str(DEFAULT_EVIDENCE_ROOT),
        help="Directory for append-only Phase 2 JSONL and SQLite evidence.",
    )


def pytest_sessionstart(session: pytest.Session) -> None:
    """Open one evidence run before test collection and execution."""
    evidence_root = Path(str(session.config.getoption("evidence_root"))).resolve()
    configured_temp = session.config.option.basetemp
    if configured_temp is not None:
        temp_root = Path(configured_temp).resolve()
        if evidence_root == temp_root or temp_root in evidence_root.parents:
            raise pytest.UsageError("Evidence root must not equal or lie inside basetemp")
        if temp_root.exists():
            raise pytest.UsageError("Refusing existing basetemp: recursive cleanup is forbidden")
    cases: dict[str, dict[str, Any]] = _EVIDENCE_CONTEXT["cases"]
    cases.clear()
    _EVIDENCE_CONTEXT["started_at"] = time.monotonic()
    _EVIDENCE_CONTEXT["store"] = EvidenceStore(
        evidence_root,
        "pytest",
        metadata={
            "rootdir": str(session.config.rootpath),
            "bridgeUrl": str(session.config.getoption("bridge_url")),
            "externalBridge": bool(session.config.getoption("external_bridge")),
            **_source_metadata(Path(session.config.rootpath)),
        },
    )


def _source_metadata(bridge_dir: Path) -> dict[str, Any]:
    """Identify dirty test source by hashes rather than inheriting a prior CI commit's result."""
    source_files = [bridge_dir / "GameTestBridge.gd", bridge_dir / "evidence_store.py",
                    bridge_dir / "protocol.schema.json",
                    *sorted((bridge_dir / "phase2_tests").glob("*.py"))]
    metadata: dict[str, Any] = {"sourceFileSha256": {
        str(path.relative_to(bridge_dir)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in source_files if path.is_file()
    }}
    try:
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=bridge_dir,
                                  capture_output=True, text=True, timeout=3, check=False)
        status = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"],
                                cwd=bridge_dir, capture_output=True, text=True,
                                timeout=3, check=False)
        metadata["gitCommit"] = revision.stdout.strip() if revision.returncode == 0 else None
        metadata["dirtyTrackedSource"] = bool(status.stdout) if status.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired) as error:
        metadata["sourceMetadataError"] = type(error).__name__
    return metadata


def pytest_runtest_logreport(report: pytest.TestReport) -> None:
    """Accumulate one final result per collected case without double counting phases."""
    current = _case_result(report.nodeid)
    current["duration_ms"] = float(current["duration_ms"]) + report.duration * 1000.0

    if report.failed:
        current["status"] = "failed"
        current["error_type"] = f"pytest_{report.when}_failure"
        current["message"] = report.longreprtext
    elif report.skipped and current["status"] != "failed":
        current["status"] = "skipped"
    elif report.when == "call" and current["status"] not in {"failed", "skipped"}:
        current["status"] = "passed"


def _case_result(nodeid: str) -> dict[str, Any]:
    """Keep response links even before pytest emits the first phase report."""
    cases: dict[str, dict[str, Any]] = _EVIDENCE_CONTEXT["cases"]
    return cases.setdefault(
        nodeid,
        {
            "status": "other", "duration_ms": 0.0,
            "error_type": None, "message": None, "response_event_ids": [],
            "transport_event_ids": [], "evidence_event_ids": [],
            "request_event_ids": [], "game_event_ids": [], "failure_event_ids": [],
            "replay_event_ids": [],
            "trace": None,
        },
    )


def _case_links(result: dict[str, Any]) -> dict[str, list[str]]:
    return {
        "requestEventIds": result["request_event_ids"],
        "responseEventIds": result["response_event_ids"],
        "transportEventIds": result["transport_event_ids"],
        "gameEventEvidenceIds": result["game_event_ids"],
        "controlledReplayEvidenceIds": result["replay_event_ids"],
        "failureEventIds": result["failure_event_ids"],
        "evidenceEventIds": result["evidence_event_ids"],
    }


class CaseEventTrace:  # pylint: disable=too-many-instance-attributes
    """Link real observations in one case without claiming temporal proximity is causality."""

    def __init__(self, case_id: str, base_url: str, schema_path: Path) -> None:
        self.case_id = case_id
        self.base_url = base_url
        self.stream = BridgeEventStream(base_url)
        self.requests: list[dict[str, Any]] = []
        self.responses: list[dict[str, Any]] = []
        self.game_events: list[dict[str, Any]] = []
        self.gaps: list[str] = []
        self.protocol_errors: list[str] = []
        self.schema_path = schema_path
        self.expected_disconnect: dict[str, Any] | None = None
        self.connection_history: list[str] = [self.stream.connection_id]
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        self.validator = Draft202012Validator({
            "$schema": schema["$schema"], "$ref": "#/$defs/event", "$defs": schema["$defs"],
        }, format_checker=FormatChecker())

    def _record(self, kind: str, **fields: Any) -> dict[str, Any]:
        store: EvidenceStore = _EVIDENCE_CONTEXT["store"]
        details = fields.pop("details", {})
        details["caseId"] = self.case_id
        event = store.record(kind, details=details, **fields)
        _case_result(self.case_id)["evidence_event_ids"].append(event["eventId"])
        return event

    def gap(self, message: str) -> None:
        """A capture problem remains explicit and makes the live case fail at teardown."""
        self.gaps.append(message)
        self._record("trace_gap", status="failed", message=message)

    def request(self, method: str, path: str, payload: Any) -> dict[str, Any]:
        """Record client intent before I/O; expected state is not observed state."""
        self.flush()
        source = payload if isinstance(payload, dict) else {}
        step_index = len(self.requests) + 1
        details = {
            "stepId": f"{self.case_id}::http-{step_index}", "stepIndex": step_index,
            "connectionId": self.stream.connection_id,
            "subscriptionState": self.stream.resource_state(),
            "expectedSessionId": source.get("expectedSessionId"),
            "expectedWorldGeneration": source.get("expectedWorldGeneration"),
            "expectedStateVersion": source.get("expectedStateVersion"),
            "commandIdSource": "client-intent" if source.get("commandId") else None,
            "requestParameters": {key: source[key] for key in (
                "commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration",
                "expectedStateVersion", "timeoutMs", "speed", "spaceId",
                "targetPosition", "tolerance",
            ) if key in source},
        }
        event = self._record(
            "bridge_request", name=f"{method.upper()} {path}",
            command_id=source.get("commandId"), details=details,
        )
        self.requests.append(event)
        _case_result(self.case_id)["request_event_ids"].append(event["eventId"])
        return event

    def flush(self, wait_seconds: float = 0.0) -> None:
        """Persist queued observations on the pytest thread, optionally allowing wire delivery."""
        deadline = time.monotonic() + wait_seconds
        while True:
            for observation in self.stream.drain():
                if "traceError" in observation:
                    expected = self.expected_disconnect
                    if (expected is not None and not expected["observed"]  # pylint: disable=too-many-boolean-expressions
                            and observation.get("connectionId") == expected["connectionId"]
                            and observation["traceError"] == "ConnectionError"
                            and observation.get("message") == "event peer disconnected"
                            and time.monotonic() <= expected["deadline"]):
                        expected["observed"] = True
                        self._record("expected_disconnect", status="observed", details={
                            **observation, "injectionEvidenceId": expected["evidenceId"],
                            "eofDeadlineSeconds": 2.0,
                            "scope": "only injected connection EOF; no global error suppression",
                        })
                        continue
                    self.gap(f"{observation['traceError']}: {observation.get('message', '')}")
                    continue
                self._game_event(observation)
            if time.monotonic() >= deadline:
                return
            time.sleep(0.01)

    def disconnect(self, mode: str) -> None:
        """Inject one real disconnect and retain the narrowly bounded expected EOF."""
        assert mode in {"client-close", "server-policy-close"}
        self.flush(0.05)
        assert not self.gaps and not self.protocol_errors
        injection = self._record("disconnect_injection", name=mode, status="started", details={
            "connectionId": self.stream.connection_id, "mode": mode,
            "before": self.stream.resource_state(), "eofDeadlineSeconds": 2.0,
        })
        self.expected_disconnect = None
        if mode == "server-policy-close":
            self.expected_disconnect = {
                "connectionId": self.stream.connection_id, "observed": False,
                "evidenceId": injection["eventId"], "deadline": time.monotonic() + 2.0,
            }
            wire = self.stream.request_policy_disconnect()
            self._record("disconnect_wire_injection", status="sent", details={
                **wire, "connectionId": self.stream.connection_id,
                "injectionEvidenceId": injection["eventId"],
            })
            while (time.monotonic() < self.expected_disconnect["deadline"]
                   and not self.expected_disconnect["observed"] and not self.gaps):
                self.flush(0.01)
            assert self.expected_disconnect["observed"], "Injected server EOF absent within 2s"
        self.stream.close()
        self.flush()
        state = self.stream.resource_state()
        self._record("disconnect_checkpoint", status="observed", details={
            **state, "injectionEvidenceId": injection["eventId"], "mode": mode,
            "readerJoinDeadlineSeconds": 1.0,
        })
        assert state["socketClosed"] and not state["readerAlive"], state
        assert not self.gaps and not self.protocol_errors

    def reconnect(self) -> None:
        """One fresh socket and handshake; failures are retained, never silently retried."""
        previous = self.stream.resource_state()
        assert previous["socketClosed"] and not previous["readerAlive"]
        self.expected_disconnect = None
        self.stream = BridgeEventStream(self.base_url)
        self.connection_history.append(self.stream.connection_id)
        attempt = self._record("reconnect_attempt", status="started", details={
            "previousConnectionId": previous["connectionId"],
            "connectionId": self.stream.connection_id, "attempt": 1, "maxAttempts": 1,
            "connectTimeoutSeconds": 3.0, "handshakeDeadlineSeconds": 3.0,
            "scope": "test-orchestrated reconnect; NOT production automatic recovery",
        })
        try:
            self.stream.start()
        except (OSError, ValueError) as error:
            self.gap(f"reconnect failed without retry: {type(error).__name__}: {error}")
            raise
        self._record("reconnect_checkpoint", status="connected", details={
            **self.stream.resource_state(), "attemptEvidenceId": attempt["eventId"],
        })

    def connection_checkpoint(self, name: str, facts: dict[str, Any]) -> dict[str, Any]:
        """Persist real HTTP facts and connection links before making test assertions."""
        return self._record("connection_checkpoint", name=name, status="observed", details={
            **facts, **self.stream.resource_state(),
            "requestEvidenceIds": [event["eventId"] for event in self.requests],
            "responseEvidenceIds": [event["eventId"] for event in self.responses],
            "gameEventEvidenceIds": [event["eventId"] for event in self.game_events],
            "connectionHistory": list(self.connection_history),
            "eventWaitSeconds": 3.0, "httpTimeoutSeconds": 5.0,
            "receiptPollingWindowSeconds": 10.0,
            "scope": "real disconnect and explicit test reconnect, no POST resend",
        })

    def resource_checkpoint(self, name: str) -> None:
        """Read owned process metrics with existing PowerShell; unavailable data stays explicit."""
        owned = _EVIDENCE_CONTEXT["bridge_processes"].get(self.base_url)
        assert owned is not None, "Disconnect validation requires this run's isolated process"
        metrics: dict[str, Any] = {}
        blind_spots = ["server internal client/object counts", "per-connection Access Log",
                      "server-to-client connection ID mapping", "long-term memory leak proof"]
        console_wrapper = Path(owned["godotExecutable"]).name.endswith("_console.exe")
        if console_wrapper:
            blind_spots.append("actual Godot child-process resource counters; "
                               "console launcher counters are NOT engine counters")
        try:
            result = subprocess.run([
                "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                f"$p=Get-Process -Id {int(owned['pid'])} -ErrorAction Stop; "
                "$p | Select-Object Id,WorkingSet64,PrivateMemorySize64,HandleCount,CPU,"
                "@{n='ThreadCount';e={$_.Threads.Count}} | ConvertTo-Json -Compress",
            ], capture_output=True, text=True, timeout=8.0, check=False)
            if result.returncode != 0:
                raise ValueError(f"process probe exit {result.returncode}")
            metrics = json.loads(result.stdout)
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            blind_spots.append(f"process counters unavailable: {type(error).__name__}: {error}")
        log = Path(owned["engineLogPath"])
        log_data = log.read_bytes() if log.is_file() else None
        self._record("resource_checkpoint", name=name, status="observed", details={
            **owned, "processMetrics": metrics, "client": self.stream.resource_state(),
            "processMetricsScope": ("console launcher only; NOT actual Godot engine"
                                    if console_wrapper else "directly launched executable"),
            "engineLogSha256AtRead": (hashlib.sha256(log_data).hexdigest()
                                      if log_data is not None else None),
            "engineLogTailAtRead": (log_data.decode("utf-8", errors="replace").splitlines()[-20:]
                                    if log_data is not None else []),
            "blindSpots": blind_spots,
            "alignment": "client UTC/4-tuple/requestId plus server response and engine log; "
                         "timestamps alone do not establish cross-end causal identity",
            "scope": "bounded samples, not a memory-leak or capacity acceptance claim",
        })

    def _game_event(self, observation: dict[str, Any]) -> None:
        source = observation["gameEvent"]
        errors = sorted(error.message for error in self.validator.iter_errors(source))
        anomalies = []
        if self.game_events:
            if source.get("eventId") in {event["details"]["gameEventId"]
                                         for event in self.game_events}:
                anomalies.append("duplicate-game-event-id")
            previous_sequence = self.game_events[-1]["eventSequence"]
            sequence = source.get("eventSequence")
            if isinstance(sequence, int) and isinstance(previous_sequence, int):
                if sequence <= previous_sequence:
                    anomalies.append("non-increasing-game-event-sequence")
                elif sequence > previous_sequence + 1:
                    anomalies.append("game-event-sequence-gap")
        matching = [request for request in self.requests
                    if source.get("commandId") is not None
                    and request["commandId"] == source.get("commandId")
                    and request["details"]["expectedSessionId"] == source.get("sessionId")]
        matching_ids = {request["eventId"] for request in matching}
        response_ids = [response["eventId"] for response in self.responses
                        if response["details"].get("requestEvidenceId") in matching_ids]
        replay = observation.get("observationSource") == "controlled-replay"
        event = self._record(
            "controlled_event_replay" if replay else "game_event",
            name=source.get("eventType"),
            status="failed" if errors else "observed",
            command_id=source.get("commandId"), session_id=source.get("sessionId"),
            world_generation=source.get("worldGeneration"),
            state_version=source.get("stateVersion"), event_sequence=source.get("eventSequence"),
            details={
                "gameEventId": source.get("eventId"), "gameEvent": source,
                "receivedAt": observation["receivedAt"], "schemaErrors": errors,
                "receiveIndex": observation["receiveIndex"],
                "wirePayloadSha256": observation["wirePayloadSha256"],
                "connectionId": observation.get("connectionId"),
                "observationSource": "controlled-replay" if replay else "live-websocket",
                "sourceEvidenceId": observation.get("sourceEvidenceId"),
                "replayScenario": observation.get("replayScenario"),
                "replayIndex": observation.get("replayIndex"),
                "sequenceObservations": anomalies,
                "stepId": (f"{self.case_id}::replay-{observation['replayScenario']}-"
                           f"{observation['replayIndex']}" if replay else
                           f"{self.case_id}::ws-{len(self.game_events) + 1}"),
                "relatedRequestEvidenceIds": [request["eventId"] for request in matching],
                "relatedStepIds": [request["details"]["stepId"] for request in matching],
                "relatedResponseEvidenceIds": response_ids,
                "association": "commandId/sessionId" if matching else "case-observation-window",
                "missingTrackingFields": [key for key in (
                    "eventId", "eventSequence", "sessionId", "worldGeneration", "stateVersion",
                ) if source.get(key) is None],
            },
        )
        self.game_events.append(event)
        if not replay:
            _case_result(self.case_id)["game_event_ids"].append(event["eventId"])
        else:
            _case_result(self.case_id)["replay_event_ids"].append(event["eventId"])
        if errors:
            self.protocol_errors.append(event["eventId"])

    def replay_observations(self, scenario: str, sources: list[dict[str, Any]],
                            order: list[int]) -> list[dict[str, Any]]:
        """Replay captured bytes' decoded events in a separate, non-network trace.

        No game event is fabricated or changed. Receive index/time/hash stay original;
        scenario/index and source evidence links identify the controlled replay.
        """
        replay = CaseEventTrace(self.case_id, self.base_url, self.schema_path)
        replay.requests = list(self.requests)
        replay.responses = list(self.responses)
        for replay_index, source_index in enumerate(order, start=1):
            original = sources[source_index]
            assert original["eventType"] == "game_event", "Only live observations may be replayed"
            details = original["details"]
            replay._game_event({  # pylint: disable=protected-access
                "gameEvent": details["gameEvent"], "receivedAt": details["receivedAt"],
                "receiveIndex": details["receiveIndex"],
                "wirePayloadSha256": details["wirePayloadSha256"],
                "observationSource": "controlled-replay", "sourceEvidenceId": original["eventId"],
                "replayScenario": scenario, "replayIndex": replay_index,
            })
        return replay.game_events

    def replay_checkpoint(self, scenario: str, observations: list[dict[str, Any]],
                          facts: dict[str, Any]) -> dict[str, Any]:
        """Link a controlled sequence to actual read-only facts, not a fake recovery outcome."""
        post_ids = {request["eventId"] for request in self.requests
                    if request["name"].startswith("POST ")}
        expected_commands = {response["commandId"] for response in self.responses
                             if response["details"].get("requestEvidenceId") in post_ids
                             and response["details"].get("receiptStatus") in {"completed", "failed"}
                             and response["commandId"] is not None}
        observed_commands = {event["commandId"] for event in observations
                             if event["name"] in {"command-completed", "command-failed"}}
        window = (_audit_event_window(facts["beforeCursor"], facts["afterCursor"],
                                     [event["details"]["gameEvent"] for event in observations])
                  if "beforeCursor" in facts else {
                      "allFramesComplete": None,
                      "completenessBlindSpot": "no cursor; command-less notifications unknown",
                  })
        return self._record("replay_checkpoint", name=scenario, status="observed", details={
            "observationSource": "controlled-replay",
            "replayEvidenceIds": [event["eventId"] for event in observations],
            "sequenceObservations": [event["details"]["sequenceObservations"]
                                     for event in observations],
            "beforeState": facts["beforeState"], "afterState": facts["afterState"],
            "actualReceipt": facts["actualReceipt"],
            "readResponseEvidenceIds": [event["eventId"] for event in self.responses[-2:]],
            "expectedTerminalCommandIds": sorted(expected_commands),
            "observedTerminalCommandIds": sorted(observed_commands),
            "missingTerminalCommandIds": sorted(expected_commands - observed_commands),
            "terminalBaselineSource": "actual terminal POST receipts, NOT hidden omitted events",
            "eventWindow": window,
            "cursorResponseEvidenceIds": facts.get("cursorResponseEvidenceIds", []),
            "allFramesComplete": window["allFramesComplete"],
            "completenessBlindSpot": window["completenessBlindSpot"],
            "scope": "test-orchestrated read-only resync; NOT production automatic recovery",
        })

    def wait_for_command(self, command_id: str, timeout_seconds: float = 3.0) -> dict[str, Any]:
        """Return the real terminal event or fail without inventing one or retrying a command."""
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            self.flush(0.02)
            for event in self.game_events:
                if event["commandId"] == command_id and event["name"] in {
                    "command-completed", "command-failed",
                }:
                    return event
        self._record("event_wait_timeout", status="failed", command_id=command_id, details={
            "timeoutSeconds": timeout_seconds, "connectionId": self.stream.connection_id,
            "meaning": "event observation timeout; NOT command business failure",
        })
        try:
            response = requests.get(f"{self.base_url}/commands/{command_id}", timeout=5.0)
            body = response.json()
            if not isinstance(body, dict):
                raise ValueError("event-timeout receipt response is not a JSON object")
            self._record("event_wait_receipt", status="observed", command_id=command_id,
                         request_id=body.get("requestId"), details={
                             "actualHttpStatus": response.status_code,
                             "responseEnvelope": body, "httpTimeoutSeconds": 5.0,
                             "meaning": "receipt evidence retained; event assertion still fails",
                         })
        except (requests.RequestException, ValueError) as error:
            self._record("event_wait_receipt", status="unavailable", command_id=command_id,
                         details={"captureError": type(error).__name__})
        pytest.fail(f"No terminal WebSocket event within {timeout_seconds}s for command "
                    f"{command_id}; query receipt to determine business status", pytrace=False)

    def capture_failure(self, report: pytest.TestReport) -> None:
        """Take a bounded post-assertion read and reference the complete observed timeline."""
        self.flush(0.15)
        snapshot_fields: dict[str, Any] = {"status": "unavailable"}
        snapshot_details: dict[str, Any] = {
            "captureTiming": "post-assertion read; not an atomic failure-time snapshot",
        }
        try:
            response = requests.get(f"{self.base_url}/world/state", timeout=2.0)
            body = response.json()
            if not isinstance(body, dict):
                raise ValueError("failure snapshot response is not a JSON object")
            data = body.get("data") if isinstance(body.get("data"), dict) else {}
            snapshot_fields.update(
                status=("captured" if response.status_code == 200 and body.get("ok")
                        else "unavailable"),
                request_id=body.get("requestId"), session_id=data.get("sessionId"),
                world_generation=data.get("worldGeneration"),
                state_version=data.get("stateVersion"),
            )
            snapshot_details.update(actualHttpStatus=response.status_code, response=body)
        except (requests.RequestException, ValueError) as error:
            snapshot_details["captureError"] = type(error).__name__
        snapshot = self._record("failure_snapshot", name="GET /world/state", **snapshot_fields,
                                details=snapshot_details)
        self.flush(0.1)
        failure = self._record(
            "assertion_failure", name=f"{self.case_id}::{report.when}", status="failed",
            message=report.longreprtext, details={
                "stepId": f"{self.case_id}::assertion-{report.when}",
                "lastObservedHttpStepId": (self.requests[-1]["details"]["stepId"]
                                           if self.requests else None),
                "phase": report.when, "snapshotEvidenceId": snapshot["eventId"],
                "requestEvidenceIds": list(_case_result(self.case_id)["request_event_ids"]),
                "responseEvidenceIds": list(_case_result(self.case_id)["response_event_ids"]),
                "gameEventEvidenceIds": list(_case_result(self.case_id)["game_event_ids"]),
                "controlledReplayEvidenceIds": list(_case_result(self.case_id)["replay_event_ids"]),
                "traceGaps": list(self.gaps),
                "protocolErrorEvidenceIds": list(self.protocol_errors),
                "connectionHistory": list(self.connection_history),
                "currentConnection": self.stream.resource_state(),
            },
        )
        _case_result(self.case_id)["failure_event_ids"].append(failure["eventId"])


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo) -> Iterator[None]:
    """Attach explicit evidence links before the JUnit plugin receives a report."""
    del call
    outcome = yield
    report = outcome.get_result()
    result = _case_result(item.nodeid)
    trace: CaseEventTrace | None = result["trace"]
    if trace is not None:
        trace.flush(0.05)
        if report.failed:
            trace.capture_failure(report)
    report.user_properties.extend([("caseId", item.nodeid), *[
        (key, json.dumps(value)) for key, value in _case_links(result).items()
    ]])


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    """Persist case outcomes and the run summary even when tests fail."""
    store: EvidenceStore | None = _EVIDENCE_CONTEXT["store"]
    if store is None:
        return

    cases: dict[str, dict[str, Any]] = _EVIDENCE_CONTEXT["cases"]
    for nodeid, result in sorted(cases.items()):
        store.record(
            "test_case",
            name=nodeid,
            status=str(result["status"]),
            duration_ms=round(float(result["duration_ms"]), 3),
            error_type=result["error_type"],
            message=result["message"],
            details={
                "framework": "pytest",
                "caseId": nodeid,
                **_case_links(result),
            },
        )

    counts = {
        status: sum(1 for result in cases.values() if result["status"] == status)
        for status in ("passed", "failed", "skipped", "other")
    }
    total = session.testscollected
    counts["other"] += max(0, total - sum(counts.values()))
    store.finish(
        status="passed" if exitstatus == pytest.ExitCode.OK else "failed",
        total=total,
        passed=counts["passed"],
        failed=counts["failed"],
        skipped=counts["skipped"],
        other=counts["other"],
        duration_ms=round(
            (time.monotonic() - float(_EVIDENCE_CONTEXT["started_at"])) * 1000.0,
            3,
        ),
    )
    _EVIDENCE_CONTEXT["store"] = None


@pytest.fixture(name="bridge_event_trace")
def fixture_bridge_event_trace(request: pytest.FixtureRequest, pytestconfig: pytest.Config
                               ) -> Iterator[CaseEventTrace | None]:
    """Require live event tracing only for existing live Bridge cases, not unit mocks."""
    if request.node.get_closest_marker("live_bridge") is None:
        yield None
        return
    fixture = ("command_bridge_base_url"
               if request.node.get_closest_marker("command_bridge") else "bridge_base_url")
    base_url = request.getfixturevalue(fixture)
    trace = CaseEventTrace(request.node.nodeid, base_url,
                           Path(pytestconfig.rootpath) / "protocol.schema.json")
    _case_result(request.node.nodeid)["trace"] = trace
    try:
        trace.stream.start()
    except (OSError, ValueError) as error:
        trace.gap(f"event subscription unavailable: {type(error).__name__}")
        pytest.fail("Live case cannot start without a real event subscription", pytrace=False)
    try:
        yield trace
    finally:
        trace.flush(0.1)
        trace.stream.close()
        trace.flush()
    if trace.gaps:
        pytest.fail(f"Event tracing gaps: {trace.gaps}", pytrace=False)
    if trace.protocol_errors:
        pytest.fail(f"Event protocol errors: {trace.protocol_errors}", pytrace=False)


def _resolve_godot_bin(config: pytest.Config) -> Path:
    configured = str(config.getoption("godot_bin")).strip()
    if configured:
        candidate = Path(configured)
    elif DEFAULT_GODOT_BIN.is_file():
        candidate = DEFAULT_GODOT_BIN
    else:
        discovered = shutil.which("godot") or shutil.which("godot4")
        if not discovered:
            pytest.fail(
                "Godot executable not found. Pass --godot-bin or use --external-bridge.",
                pytrace=False,
            )
        candidate = Path(discovered)

    if not candidate.is_file():
        pytest.fail(f"Godot executable does not exist: {candidate}", pytrace=False)
    return candidate


@pytest.fixture
def godot_executable(pytestconfig: pytest.Config) -> Path:
    """Reuse the existing executable resolver for read-only save validation."""
    return _resolve_godot_bin(pytestconfig)


def _capture_output(process: subprocess.Popen[str], lines: collections.deque[str]) -> None:
    if process.stdout is None:
        return
    for line in process.stdout:
        lines.append(line.rstrip())


def _wait_until_ready(
    process: subprocess.Popen[str] | None,
    base_url: str,
    lines: collections.deque[str],
    timeout_seconds: float = 45.0,
) -> None:
    deadline = time.monotonic() + timeout_seconds
    last_error = "bridge did not answer"
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            log_tail = "\n".join(lines)
            pytest.fail(
                f"Isolated Godot fixture exited with code {process.returncode}.\n{log_tail}",
                pytrace=False,
            )
        try:
            response = requests.get(f"{base_url}/world/state", timeout=1.0)
            if response.status_code == 200:
                return
            last_error = f"HTTP {response.status_code}: {response.text[:200]}"
        except requests.RequestException as exc:
            last_error = str(exc)
        time.sleep(0.2)

    log_tail = "\n".join(lines)
    pytest.fail(
        f"GameTestBridge was not ready within {timeout_seconds:.0f}s: {last_error}\n{log_tail}",
        pytrace=False,
    )


@contextmanager
def _isolated_bridge(
    pytestconfig: pytest.Config,
    *,
    command_mode: bool,
) -> Iterator[str]:
    """Run one module-scoped isolated bridge in read-only or command mode."""
    base_url = str(pytestconfig.getoption("bridge_url")).rstrip("/")
    if pytestconfig.getoption("external_bridge"):
        _wait_until_ready(None, base_url, collections.deque(maxlen=1))
        yield base_url
        return

    godot_bin = _resolve_godot_bin(pytestconfig)
    location = urlsplit(base_url)
    if location.scheme != "http" or location.hostname not in {"127.0.0.1", "localhost"}:
        pytest.fail("Isolated Bridge requires an explicit loopback URL", pytrace=False)
    try:
        with socket.create_connection((location.hostname, location.port or 80), timeout=3.0):
            pytest.fail("Refusing occupied Bridge port before starting or mutating a fixture",
                        pytrace=False)
    except ConnectionRefusedError:
        pass
    # The reporter acceptance child copies conftest into an artifact directory;
    # the checked-in pytest.ini remains the source of the real project location.
    game_dir = Path(pytestconfig.rootpath).parent
    if not (game_dir / "tests" / "game_test_bridge_test.gd").is_file():
        pytest.fail("Use the checked-in game/test_bridge/pytest.ini", pytrace=False)
    store: EvidenceStore = _EVIDENCE_CONTEXT["store"]
    engine_log = store.root / f"{new_run_id('godot-bridge')}.log"
    if engine_log.exists():
        pytest.fail("Refusing to overwrite an existing engine log", pytrace=False)
    command = [
        str(godot_bin),
        "--headless",
        "--path",
        str(game_dir),
        "--log-file",
        str(engine_log),
        "--script",
        "res://tests/game_test_bridge_test.gd",
        "--",
        "--gametest-isolated-test",
        "--bridge-smoke-server",
        "--bridge-smoke-long",
    ]
    if command_mode:
        command.append("--bridge-smoke-commands")
    # Popen intentionally spans the fixture yield and is closed in finally.
    process = subprocess.Popen(  # pylint: disable=consider-using-with
        command,
        cwd=game_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    lines: collections.deque[str] = collections.deque(maxlen=200)
    reader = threading.Thread(target=_capture_output, args=(process, lines), daemon=True)
    reader.start()
    _EVIDENCE_CONTEXT["bridge_processes"][base_url] = {
        "pid": process.pid, "engineLogPath": str(engine_log),
        "godotExecutable": str(godot_bin),
        "ownership": "this pytest run isolated Godot subprocess",
    }

    try:
        _wait_until_ready(process, base_url, lines)
        yield base_url
    finally:
        _EVIDENCE_CONTEXT["bridge_processes"].pop(base_url, None)
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


@pytest.fixture(scope="module")
def bridge_base_url(pytestconfig: pytest.Config) -> Iterator[str]:
    """Start the read-only isolated bridge for one test module."""
    with _isolated_bridge(pytestconfig, command_mode=False) as base_url:
        yield base_url


@pytest.fixture(scope="module")
def command_bridge_base_url(pytestconfig: pytest.Config) -> Iterator[str]:
    """Start an isolated bridge with explicitly enabled write commands."""
    with _isolated_bridge(pytestconfig, command_mode=True) as base_url:
        yield base_url


@pytest.fixture(name="record_bridge_response")
def fixture_record_bridge_response(
    request: pytest.FixtureRequest,
    bridge_event_trace: CaseEventTrace | None,
) -> Callable[[str, requests.Response, int], None]:
    """Persist Bridge correlation fields beside the pytest case result."""

    def record(name: str, response: requests.Response, expected_status: int) -> None:
        store: EvidenceStore | None = _EVIDENCE_CONTEXT["store"]
        if store is None:
            return
        decode_error = None
        try:
            body = response.json()
            if not isinstance(body, dict):
                body = {}
                decode_error = "JSON response is not an object"
        except ValueError:
            body = {}
            decode_error = "Response is not valid JSON"
        data = body.get("data") if isinstance(body.get("data"), dict) else {}
        error = body.get("error") if isinstance(body.get("error"), dict) else {}
        result = _case_result(request.node.nodeid)
        request_event = getattr(response, "gametest_request_evidence", None)
        step_index = (request_event["details"]["stepIndex"] if request_event
                      else len(result["evidence_event_ids"]) + 1)
        event = store.record(
            "bridge_response",
            name=name,
            status="passed" if response.status_code == expected_status else "failed",
            error_type=error.get("code"),
            message=error.get("message"),
            request_id=body.get("requestId"),
            command_id=data.get("commandId"),
            session_id=data.get("sessionId"),
            world_generation=data.get("worldGeneration"),
            state_version=data.get("stateVersion"),
            details={
                "caseId": request.node.nodeid,
                "stepId": (request_event["details"]["stepId"] if request_event
                           else f"{request.node.nodeid}::response-{step_index}"),
                "stepIndex": step_index,
                "requestEvidenceId": request_event["eventId"] if request_event else None,
                "expectedHttpStatus": expected_status,
                "actualHttpStatus": response.status_code,
                "responseDecodeError": decode_error,
                "receiptStatus": data.get("status"),
                "responseEnvelope": body,
            },
        )
        result["response_event_ids"].append(event["eventId"])
        result["evidence_event_ids"].append(event["eventId"])
        if bridge_event_trace is not None:
            bridge_event_trace.responses.append(event)
            bridge_event_trace.flush()

    return record


@pytest.fixture(name="record_bridge_transport_error")
def fixture_record_bridge_transport_error(
    request: pytest.FixtureRequest,
    bridge_event_trace: CaseEventTrace | None,
) -> Callable[[str, requests.RequestException, float], None]:
    """Record a failed attempt without inventing any server-issued correlation ID."""
    def record(name: str, error: requests.RequestException, duration_ms: float) -> None:
        store: EvidenceStore | None = _EVIDENCE_CONTEXT["store"]
        if store is None:
            return
        result = _case_result(request.node.nodeid)
        step_index = len(result["evidence_event_ids"]) + 1
        request_event = (
            bridge_event_trace.requests[-1]
            if bridge_event_trace is not None and bridge_event_trace.requests else None
        )
        event = store.record(
            "bridge_transport_error", name=name, status="failed",
            error_type=type(error).__name__, duration_ms=round(duration_ms, 3),
            message="No usable HTTP response; original exception re-raised",
            details={
                "caseId": request.node.nodeid,
                "stepId": f"{request.node.nodeid}::transport-{step_index}",
                "stepIndex": step_index, "actualHttpStatus": None,
                "requestEvidenceId": request_event["eventId"] if request_event else None,
            },
        )
        result["transport_event_ids"].append(event["eventId"])
        result["evidence_event_ids"].append(event["eventId"])

    return record


@pytest.fixture
def http_session(
    record_bridge_transport_error: Callable[[str, requests.RequestException, float], None],
    bridge_event_trace: CaseEventTrace | None,
) -> Iterator[requests.Session]:
    """Bind failed HTTP attempts to the case while keeping normal response recording explicit."""
    session = requests.Session()
    session.headers.update({"Accept": "application/json"})
    original_request = session.request

    def traced_request(method: str, url: str, *args: Any, **kwargs: Any) -> requests.Response:
        started_at = time.monotonic()
        request_event = None
        if bridge_event_trace is not None:
            if not url.startswith(bridge_event_trace.base_url + "/"):
                raise ValueError("live case request is outside its subscribed Bridge")
            request_event = bridge_event_trace.request(
                method, urlsplit(url).path, kwargs.get("json"),
            )
        try:
            response = original_request(method, url, *args, **kwargs)
            if request_event is not None:
                response.gametest_request_evidence = request_event
            return response
        except requests.RequestException as error:
            # Paths only: credentials, query values and response bodies are not logged.
            try:
                path = urlsplit(url).path or "/"
            except ValueError:
                path = "<invalid-url>"
            record_bridge_transport_error(
                f"{method.upper()} {path}", error, (time.monotonic() - started_at) * 1000,
            )
            raise

    session.request = traced_request
    try:
        yield session
    finally:
        session.close()
