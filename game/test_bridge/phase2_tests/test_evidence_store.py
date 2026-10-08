"""Contract tests for append-only Phase 2 evidence persistence."""

from __future__ import annotations

import json
import hashlib
import shutil
import socket
import sqlite3
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
# Pylint 2.14 on this Windows runtime misses os.environ; verified as os._Environ.
from os import environ  # pylint: disable=no-name-in-module

import pytest
from jsonschema import Draft202012Validator, FormatChecker

from game.test_bridge.evidence_store import EvidenceStore  # pylint: disable=import-error


def test_real_world_generation_transition_rejects_old_command(  # pylint: disable=too-many-locals,too-many-statements
    tmp_path: Path, godot_executable: Path, request: pytest.FixtureRequest, cursor_replay_evidence,
) -> None:
    """Real in-memory World restart and wire observations, NOT save/load or Agent recovery."""
    game_root = Path(__file__).resolve().parents[2]
    bridge_source = game_root / "test_bridge/GameTestBridge.gd"
    world_source = game_root / "world/runtime/TownWorldRuntime.gd"
    protected = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in (bridge_source, world_source)}
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    script = tmp_path / "world-generation-wire.gd"
    driver = r'''extends "res://tests/game_test_bridge_test.gd"
func _run_bridge_tests() -> void:
	_port = $PORT
	var data = _build_data()
	var opening = _load_opening(data)
	_world = WORLD.new()
	_expect(_world.call("start", data, opening).get("ok", false), "world starts")
	_bridge = BRIDGE.new()
	root.add_child(_bridge)
	var started = _bridge.start(_context, _port, true)
	if not started.get("ok", false):
		_bridge.free()
		quit(1)
		return
	var initial_cursor = await _exchange(_header("/events/cursor"))
	var peer = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", _port)
	var deadline = Time.get_ticks_msec() + 5000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		await process_frame
	var headers = "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
	headers += "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
	peer.put_data(_header("/events", "GET", headers).to_utf8_buffer())
	var handshake = PackedByteArray()
	while handshake.get_string_from_ascii().find("\r\n\r\n") < 0 and Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_bytes() > 0:
			handshake.append_array(peer.get_data(peer.get_available_bytes())[1])
		await process_frame
	_expect(handshake.get_string_from_ascii().begins_with("HTTP/1.1 101 "), "real handshake")
	var before = await _exchange(_header("/world/state"))
	var old_command = _command("epoch-before", 2)
	var old_receipt = await _exchange(_post(old_command))
	var events = [await _read_websocket_event(peer), await _read_websocket_event(peer)]
	var old_state = await _exchange(_header("/world/state"))
	var old_cursor = await _exchange(_header("/events/cursor"))
	_world.call("stop")
	var stopped_cursor = await _exchange(_header("/events/cursor"))
	_expect(_world.call("start", data, opening).get("ok", false), "same world restarts")
	await process_frame
	var new_state = await _exchange(_header("/world/state"))
	var new_cursor = await _exchange(_header("/events/cursor"))
	events.append(await _read_websocket_event(peer))
	var stale = _command("epoch-stale", 3)
	stale.expectedWorldGeneration = old_state.body.data.worldGeneration
	var rejected = await _exchange(_post(stale))
	var after_reject = await _exchange(_header("/world/state"))
	var fresh = _command("epoch-fresh", 3)
	var fresh_receipt = await _exchange(_post(fresh))
	events.append(await _read_websocket_event(peer))
	events.append(await _read_websocket_event(peer))
	var final_state = await _exchange(_header("/world/state"))
	var final_cursor = await _exchange(_header("/events/cursor"))
	peer.disconnect_from_host()
	_bridge.stop()
	_expect(_bridge.start(_context, _port, true).get("ok", false), "relisten")
	var relisten_cursor = await _exchange(_header("/events/cursor"))
	_bridge.stop()
	_bridge.free()
	_bridge = BRIDGE.new()
	root.add_child(_bridge)
	_expect(_bridge.start(_context, _port, true).get("ok", false), "new bridge starts")
	var replacement_cursor = await _exchange(_header("/events/cursor"))
	print("WORLD_GENERATION_WIRE " + JSON.stringify({
		"before": before, "oldState": old_state, "newState": new_state,
		"oldCommand": old_command, "oldReceipt": old_receipt,
		"staleCommand": stale, "rejected": rejected, "afterReject": after_reject,
		"freshCommand": fresh, "freshReceipt": fresh_receipt,
		"initialCursor": initial_cursor, "oldCursor": old_cursor, "stoppedCursor": stopped_cursor,
		"newCursor": new_cursor, "finalCursor": final_cursor, "relistenCursor": relisten_cursor,
		"replacementCursor": replacement_cursor, "finalState": final_state, "events": events}))
	_bridge.stop()
	_bridge.free()
	_world.call("stop")
	_finish_suite("WORLD_GENERATION_WIRE_PASS")'''
    script.write_text(driver.replace("$PORT", str(port)), encoding="utf-8")
    started_at = time.monotonic()
    completed = subprocess.run(
        [str(godot_executable), "--headless", "--path", str(game_root),
         "--log-file", str(tmp_path / "godot-engine.log"), "--script", str(script),
         "--", "--gametest-isolated-test"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=40, check=False, env={**environ, "AI_TOWN_PROVIDER_TEST_NO_NETWORK": "1"},
    )
    output = completed.stdout + completed.stderr
    (tmp_path / "godot-output.log").write_text(output, encoding="utf-8")
    lines = [line.removeprefix("WORLD_GENERATION_WIRE ") for line in output.splitlines()
             if line.startswith("WORLD_GENERATION_WIRE ")]
    facts = json.loads(lines[0]) if len(lines) == 1 else {}
    evidence = EvidenceStore(tmp_path / "evidence", "godot-generation-wire", metadata={
        "parentCaseId": request.node.nodeid, "protectedSourceSha256": protected,
        "driverSha256": hashlib.sha256(script.read_bytes()).hexdigest(),
        "scope": "actual World stop/start and TCP/WS; NOT save/load, Mock or Agent Recovery",
    })
    request.node.user_properties.extend([
        ("childRunId", evidence.run_id), ("childEvidenceJsonl", str(evidence.jsonl_path)),
    ])
    experiment = evidence.record("generation_experiment", status="observed", details={
        "actualExitCode": completed.returncode, "facts": facts,
        "outputLog": str(tmp_path / "godot-output.log"),
    })
    schema = json.loads((game_root / "test_bridge/protocol.schema.json").read_text("utf-8"))
    validator = Draft202012Validator({"$schema": schema["$schema"], "$ref": "#/$defs/event",
                                      "$defs": schema["$defs"]}, format_checker=FormatChecker())
    events = facts.get("events", [])
    schema_errors = [error.message for event in events for error in validator.iter_errors(event)]
    observed_events = []
    for index, event in enumerate(events):
        observed_events.append(evidence.record("game_event", name=event.get("eventType"),
                        command_id=event.get("commandId"), session_id=event.get("sessionId"),
                        world_generation=event.get("worldGeneration"),
                        state_version=event.get("stateVersion"),
                        event_sequence=event.get("eventSequence"), details={
                            "gameEvent": event, "gameEventId": event.get("eventId"),
                            "receiveIndex": index + 1, "observationSource": "godot-real-websocket",
                            "wirePayloadSha256": None,
                            "blindSpot": "existing Godot decoder does not retain raw frame bytes",
                        }))
    def state(key: str) -> dict:
        return facts.get(key, {}).get("body", {}).get("data", {})
    old, new, after = state("oldState"), state("newState"), state("afterReject")
    identity = ("sessionId", "worldGeneration", "stateVersion", "simulationSpeed", "residentCount")
    checks = {
        "engine-exit-and-output": completed.returncode == 0 and len(lines) == 1
                                  and "SCRIPT ERROR" not in output,
        "world-generation-changes": bool(old.get("worldGeneration"))
                                    and old.get("worldGeneration") != new.get("worldGeneration"),
        "same-session": bool(old.get("sessionId")) and old.get("sessionId") == new.get("sessionId"),
        "stale-command-rejected": facts.get("rejected", {}).get("status") == 409
                                  and facts.get("rejected", {}).get("body", {}).get("error", {})
                                  .get("code") == "WORLD_GENERATION_CONFLICT",
        "rejection-no-state-mutation": bool(new) and all(new.get(key) == after.get(key)
                                                        for key in identity),
        "resident-count-preserved": all(state(key).get("residentCount") == 15
                                         for key in ("before", "oldState", "newState",
                                                     "afterReject", "finalState")),
        "event-schema": len(events) == 5 and not schema_errors,
        "old-and-new-event-generations": len(events) == 5
            and all(event.get("worldGeneration") == old.get("worldGeneration")
                    for event in events[:2])
            and all(event.get("worldGeneration") == new.get("worldGeneration")
                    for event in events[2:]),
        "epoch-transition-linked": len(events) == 5
            and events[2].get("eventType") == "state-version-changed"
            and events[2].get("previousWorldGeneration") == old.get("worldGeneration"),
        "new-command-and-event": len(events) == 5
            and events[3].get("eventType") == "command-completed"
            and events[3].get("commandId") == facts.get("freshCommand", {}).get("commandId")
            and events[3].get("stateVersion") == state("freshReceipt").get("stateVersion")
            and state("freshReceipt").get("status") == "completed"
            and state("finalState").get("simulationSpeed") == 3,
        "source-unmodified": all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
                                 for path, digest in protected.items()),
    }
    sequences = [event.get("eventSequence") for event in events]
    checks["bridge-sequence-continues-across-world-epoch"] = (
        len(events) == 5 and not schema_errors
        and all(current > previous for previous, current in zip(sequences, sequences[1:]))
        and len({event.get("eventId") for event in events}) == 5)
    response_validator = Draft202012Validator(schema, format_checker=FormatChecker())
    cursor_keys = ("initialCursor", "oldCursor", "stoppedCursor", "newCursor",
                   "finalCursor", "relistenCursor", "replacementCursor")
    cursor_errors = [error.message for key in cursor_keys
                     for error in response_validator.iter_errors(facts.get(key, {}).get("body"))]
    checks["cursor-response-schema"] = not cursor_errors
    checks["cursor-unready-rejected"] = facts.get("stoppedCursor", {}).get("status") == 503 and (
        facts.get("stoppedCursor", {}).get("body", {}).get("error", {}).get("code")
        == "WORLD_NOT_READY")
    windows = []
    if len(events) == 5 and not schema_errors and not cursor_errors:
        cursors = {key: state(key) for key in cursor_keys}
        cursors["experimentEvidenceId"] = experiment["eventId"]
        windows, changed_stream = cursor_replay_evidence(evidence, events, observed_events, cursors)
        checks["replacement-stream-not-merged"] = changed_stream["allFramesComplete"] is None
    checks["commandless-boundary-detection"] = len(windows) == 4 and (
        [window["allFramesComplete"] for window in windows] == [True, False, False, False]
        and windows[1]["missingEventSequences"] == [events[2]["eventSequence"]]
        and windows[2]["missingEventSequences"] == [events[4]["eventSequence"]]
        and "commandId" not in events[2] and "commandId" not in events[4])
    checks["cursor-zero-and-epoch-continuity"] = not cursor_errors and (
        state("initialCursor").get("lastEmittedEventSequence") == 0
        and state("oldCursor").get("lastEmittedEventSequence") == events[1]["eventSequence"]
        and state("newCursor").get("lastEmittedEventSequence") == events[2]["eventSequence"]
        and state("finalCursor").get("lastEmittedEventSequence") == events[-1]["eventSequence"]
        and state("oldCursor").get("streamId") == state("finalCursor").get("streamId")
        and state("oldCursor").get("worldGeneration") == old.get("worldGeneration")
        and state("newCursor").get("worldGeneration") == new.get("worldGeneration"))
    checks["bridge-object-lifetime-cursor"] = not cursor_errors and (
        state("relistenCursor").get("streamId") == state("finalCursor").get("streamId")
        and state("relistenCursor").get("lastEmittedEventSequence") == events[-1]["eventSequence"]
        and state("replacementCursor").get("streamId") != state("finalCursor").get("streamId")
        and state("replacementCursor").get("lastEmittedEventSequence") == 0)
    for name, passed in checks.items():
        evidence.record("test_case", name=name, status="passed" if passed else "failed",
                        details={"factsEvidenceScope": "real driver output",
                                 "schemaErrors": schema_errors})
    evidence.finish(status="passed" if all(checks.values()) else "failed", total=len(checks),
                    passed=sum(checks.values()), failed=sum(not value for value in checks.values()),
                    skipped=0, other=0,
                    duration_ms=round((time.monotonic() - started_at) * 1000, 3))
    assert all(checks.values()), {"checks": checks, "facts": facts, "output": output}


def test_jsonl_and_sqlite_store_the_same_traceable_run(tmp_path: Path) -> None:
    """One normalized payload must feed both evidence formats."""
    store = EvidenceStore(
        tmp_path,
        "pytest",
        run_id="pytest-fixed-run",
        metadata={"suite": "unit"},
    )
    case_event = store.record(
        "test_case",
        name="example::case",
        status="failed",
        duration_ms=12.5,
        error_type="AssertionError",
        message="expected 15 residents",
        request_id="request-1",
        command_id=None,
        session_id="session-1",
        world_generation="world-1",
        state_version=42,
        event_sequence=None,
        details={"phase": "call"},
    )
    store.finish(
        status="failed",
        total=1,
        passed=0,
        failed=1,
        skipped=0,
        other=0,
        duration_ms=15.0,
    )
    jsonl_events = [
        json.loads(line)
        for line in store.jsonl_path.read_text(encoding="utf-8").splitlines()
    ]
    assert [event["eventType"] for event in jsonl_events] == [
        "run_started",
        "test_case",
        "run_finished",
    ]
    assert jsonl_events[1] == case_event
    assert jsonl_events[1]["commandId"] is None
    assert jsonl_events[1]["eventSequence"] is None
    with sqlite3.connect(store.sqlite_path) as connection:
        run_row = connection.execute(
            """
            SELECT status, total, passed, failed, skipped, other, duration_ms
            FROM runs WHERE run_id = ?
            """,
            (store.run_id,),
        ).fetchone()
        event_row = connection.execute(
            """
            SELECT event_type, status, request_id, command_id, state_version,
                   details_json
            FROM evidence_events
            WHERE run_id = ? AND event_type = 'test_case'
            """,
            (store.run_id,),
        ).fetchone()
    assert run_row == ("failed", 1, 0, 1, 0, 0, 15.0)
    assert event_row == (
        "test_case",
        "failed",
        "request-1",
        None,
        42,
        '{"phase":"call"}',
    )


def test_finished_store_rejects_late_evidence(tmp_path: Path) -> None:
    """Late writes must not make JSONL and SQLite disagree."""
    store = EvidenceStore(tmp_path, "pytest", run_id="pytest-finished-run")
    store.finish(
        status="passed",
        total=0,
        passed=0,
        failed=0,
        skipped=0,
        other=0,
        duration_ms=1.0,
    )
    with pytest.raises(RuntimeError, match="run has finished"):
        store.record("test_case", name="too-late", status="passed")


def test_pytest_failure_links_responses_in_jsonl_sqlite_and_junit(tmp_path: Path) -> None:
    """A real child pytest failure must retain all response links, not just the last."""
    child_root = tmp_path / "trace-child"
    child_root.mkdir()
    suite_root = Path(__file__).resolve().parent
    shutil.copyfile(suite_root / "conftest.py", child_root / "conftest.py")
    child_test = child_root / "test_controlled_trace.py"
    child_test.write_text(
        '''import json
import socket
import pytest
import requests

def response(payload):
    value = requests.Response()
    value.status_code = 200
    value._content = payload.encode("utf-8")
    return value

def test_controlled_failure(record_bridge_response):
    for number in (1, 2):
        payload = {"requestId": f"request-{number}", "data": {
            "commandId": f"command-{number}", "sessionId": "session-1",
            "worldGeneration": "world-1", "stateVersion": number}}
        record_bridge_response("GET /same-path", response(json.dumps(payload)), 200)
    assert False, "controlled business assertion failure"

def test_same_path_different_case(record_bridge_response):
    record_bridge_response("GET /same-path", response('{"requestId":"request-other"}'), 200)

@pytest.mark.parametrize("payload", ["null", "[]", "not-json"])
def test_malformed_capture_does_not_hide_failure(record_bridge_response, payload):
    record_bridge_response("GET /invalid-body", response(payload), 200)

def test_unhandled_timeout(http_session, monkeypatch):
    def timed_out(*args, **kwargs):
        raise requests.ReadTimeout("synthetic timeout with token=private")
    monkeypatch.setattr(http_session, "send", timed_out)
    http_session.get("http://127.0.0.1:1/world/state?token=private", timeout=0.1)

def test_unreachable_listener(http_session):
    with socket.socket() as unused_listener:
        unused_listener.bind(("127.0.0.1", 0))
        port = unused_listener.getsockname()[1]
        with pytest.raises(requests.ConnectionError):
            http_session.get(f"http://127.0.0.1:{port}/health", timeout=0.5)
''',
        encoding="utf-8",
    )
    evidence_root = child_root / "evidence"
    junit_path = child_root / "junit.xml"
    completed = subprocess.run(
        [
            sys.executable, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
            "-c", str(suite_root.parent / "pytest.ini"), str(child_test),
            "--evidence-root", str(evidence_root), "--junitxml", str(junit_path),
            "--basetemp", str(child_root / "pytest-temp"),
        ],
        cwd=suite_root.parents[2], capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=30, check=False,
    )
    assert completed.returncode == 1, completed.stdout + completed.stderr
    jsonl_paths = list(evidence_root.glob("pytest-*.jsonl"))
    assert len(jsonl_paths) == 1
    events = [json.loads(line) for line in jsonl_paths[0].read_text("utf-8").splitlines()]
    failed_case = next(
        event for event in events
        if event["eventType"] == "test_case"
        and event["name"].endswith("::test_controlled_failure")
    )
    failed_id = failed_case["details"]["caseId"]
    response_ids = failed_case["details"]["responseEventIds"]
    responses = [event for event in events if event["eventId"] in response_ids]
    assert [event["requestId"] for event in responses] == ["request-1", "request-2"]
    assert [event["commandId"] for event in responses] == ["command-1", "command-2"]
    assert [event["details"]["stepIndex"] for event in responses] == [1, 2]
    assert all(event["details"]["caseId"] == failed_id for event in responses)
    assert len({event["details"]["stepId"] for event in responses}) == 2
    malformed = [event for event in events if event["name"] == "GET /invalid-body"]
    assert len(malformed) == 3
    assert all(event["requestId"] is None for event in malformed)
    assert all(event["details"]["responseDecodeError"] for event in malformed)
    _assert_persisted_failure(evidence_root, junit_path, failed_id, response_ids)
    _assert_transport_failure(events, evidence_root, junit_path)


def _assert_persisted_failure(
    evidence_root: Path, junit_path: Path, failed_id: str, response_ids: list[str],
) -> None:
    """Compare the failed case's SQL and JUnit links with its JSONL event IDs."""
    with sqlite3.connect(evidence_root / "phase2_evidence.sqlite3") as connection:
        sql_response_ids = [row[0] for row in connection.execute(
            "SELECT event_id FROM evidence_events WHERE event_type='bridge_response' "
            "AND json_extract(details_json, '$.caseId')=? ORDER BY sequence",
            (failed_id,),
        )]
        run_counts = connection.execute(
            "SELECT status,total,passed,failed,skipped FROM runs",
        ).fetchone()
    assert sql_response_ids == response_ids
    assert run_counts == ("failed", 7, 5, 2, 0)
    failed_xml = next(
        case for case in ET.parse(junit_path).iter("testcase")
        if case.get("name") == "test_controlled_failure"
    )
    properties = {item.get("name"): item.get("value")
                  for item in failed_xml.findall("properties/property")}
    assert properties["caseId"] == failed_id
    assert json.loads(properties["responseEventIds"]) == response_ids


def _assert_transport_failure(events: list[dict], evidence_root: Path, junit_path: Path) -> None:
    """Timeouts and an unreachable local listener retain links with null server IDs."""
    attempts = [event for event in events if event["eventType"] == "bridge_transport_error"]
    assert len(attempts) == 2
    assert attempts[0]["errorType"] == "ReadTimeout"
    # A bound non-listening socket may time out on Windows or refuse on other hosts.
    assert attempts[1]["errorType"] in {"ConnectionError", "ConnectTimeout"}
    assert all(event["durationMs"] >= 0 for event in attempts)
    for attempt in attempts:
        assert all(attempt[field] is None for field in (
            "requestId", "commandId", "sessionId", "worldGeneration",
            "stateVersion", "eventSequence",
        ))
        assert "private" not in json.dumps(attempt)
        case = next(event for event in events if event["eventType"] == "test_case"
                    and event["name"] == attempt["details"]["caseId"])
        assert case["details"]["responseEventIds"] == []
        assert case["details"]["transportEventIds"] == [attempt["eventId"]]
        assert case["details"]["evidenceEventIds"] == [attempt["eventId"]]
        expected_status = "failed" if attempt["errorType"] == "ReadTimeout" else "passed"
        assert case["status"] == expected_status
    with sqlite3.connect(evidence_root / "phase2_evidence.sqlite3") as connection:
        rows = connection.execute(
            "SELECT event_id, request_id, command_id FROM evidence_events "
            "WHERE event_type='bridge_transport_error' ORDER BY sequence",
        ).fetchall()
    assert rows == [(event["eventId"], None, None) for event in attempts]
    timeout_xml = next(case for case in ET.parse(junit_path).iter("testcase")
                       if case.get("name") == "test_unhandled_timeout")
    properties = {item.get("name"): item.get("value")
                  for item in timeout_xml.findall("properties/property")}
    assert timeout_xml.find("failure") is not None
    assert json.loads(properties["transportEventIds"]) == [attempts[0]["eventId"]]


def test_real_failure_retains_snapshot_and_websocket_timeline(
    tmp_path: Path, godot_executable: Path,
) -> None:
    """A deliberate child assertion failure must reference real isolated-game evidence.

    This is a reporter acceptance experiment, not a newly discovered product bug.
    No fake HTTP responses, injected game events or real save files are used.
    """
    child_root = tmp_path / "real-event-child"
    child_root.mkdir()
    suite_root = Path(__file__).resolve().parent
    shutil.copyfile(suite_root / "conftest.py", child_root / "conftest.py")
    child_test = child_root / "test_real_failure.py"
    child_test.write_text(
        '''import pytest
from game.test_bridge.phase2_tests.test_bridge_command_api import _world, _command, _json_request

pytestmark = [pytest.mark.live_bridge, pytest.mark.command_bridge]

def test_controlled_real_failure(http_session, command_bridge_base_url,
                                record_bridge_response, bridge_event_trace):
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    command = {**_command(before), "speed": 2 if before["simulationSpeed"] != 2 else 3}
    response = _json_request(http_session, record_bridge_response, "POST",
                             command_bridge_base_url, "/commands/set-speed", 200, payload=command)
    event = bridge_event_trace.wait_for_command(command["commandId"])
    assert event["details"]["gameEvent"]["result"] == response["data"]["result"]
    assert response["data"]["result"]["simulationSpeed"] == 4, (
        "intentional reporter acceptance failure")

def test_other_case_is_not_the_failed_case(http_session, command_bridge_base_url,
                                          record_bridge_response):
    after = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after["residentCount"] == 15
''', encoding="utf-8",
    )
    evidence_root = child_root / "evidence"
    junit_path = child_root / "junit.xml"
    completed = subprocess.run(
        [sys.executable, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
         "-c", str(suite_root.parent / "pytest.ini"), str(child_test),
         "--godot-bin", str(godot_executable),
         "--evidence-root", str(evidence_root), "--junitxml", str(junit_path),
         "--basetemp", str(child_root / "fresh-pytest-temp")],
        cwd=suite_root.parents[2], capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=90, check=False,
    )
    (child_root / "child-output.log").write_text(completed.stdout + completed.stderr,
                                                encoding="utf-8")
    assert completed.returncode == 1, completed.stdout + completed.stderr
    jsonl_paths = list(evidence_root.glob("pytest-*.jsonl"))
    assert len(jsonl_paths) == 1
    events = [json.loads(line) for line in jsonl_paths[0].read_text("utf-8").splitlines()]
    _assert_real_failure_trace(events, evidence_root, junit_path)


def _assert_real_failure_trace(  # pylint: disable=too-many-locals
    events: list[dict], evidence_root: Path, junit_path: Path,
) -> None:
    """Verify the actual request/event/snapshot links in JSONL, SQL and failing JUnit."""
    index = {event["eventId"]: event for event in events}
    failures = [event for event in events if event["eventType"] == "assertion_failure"]
    call_failures = [event for event in failures if event["details"]["phase"] == "call"]
    assert len(call_failures) == 1
    failure = call_failures[0]
    case_id = failure["details"]["caseId"]
    assert case_id.endswith("::test_controlled_real_failure")
    snapshot = index[failure["details"]["snapshotEvidenceId"]]
    assert snapshot["eventType"] == "failure_snapshot"
    assert snapshot["status"] == "captured"
    assert snapshot["requestId"]
    assert snapshot["details"]["response"]["data"]["residentCount"] == 15
    observed = [index[event_id] for event_id in failure["details"]["gameEventEvidenceIds"]]
    terminal = next(event for event in observed if event["name"] == "command-completed")
    schema_path = Path(__file__).resolve().parents[1] / "protocol.schema.json"
    schema = json.loads(schema_path.read_text("utf-8"))
    validator = Draft202012Validator({
        "$schema": schema["$schema"], "$ref": "#/$defs/event", "$defs": schema["$defs"],
    }, format_checker=FormatChecker())
    assert terminal["details"]["schemaErrors"] == sorted(
        error.message for error in validator.iter_errors(terminal["details"]["gameEvent"])
    )
    # Reporter acceptance must preserve, not suppress, any actual protocol failures.
    protocol_failures = [event for event in failures if event["details"]["phase"] == "teardown"]
    assert len(protocol_failures) == (1 if terminal["details"]["schemaErrors"] else 0)
    if protocol_failures:
        assert "Event protocol errors" in protocol_failures[0]["message"]
        assert terminal["eventId"] in protocol_failures[0]["details"]["protocolErrorEvidenceIds"]
    assert terminal["worldGeneration"] == snapshot["worldGeneration"]
    assert terminal["stateVersion"] == snapshot["stateVersion"]
    assert terminal["eventSequence"] == terminal["details"]["gameEvent"]["eventSequence"] > 0
    assert terminal["eventId"] != terminal["details"]["gameEventId"]
    assert terminal["testEvidenceId"] == terminal["eventId"]
    assert terminal["details"]["missingTrackingFields"] == []
    requests_for_event = [index[event_id] for event_id in
                          terminal["details"]["relatedRequestEvidenceIds"]]
    assert len(requests_for_event) == 1
    request_event = requests_for_event[0]
    assert request_event["name"] == "POST /commands/set-speed"
    assert request_event["commandId"] == terminal["commandId"]
    assert (request_event["details"]["requestParameters"]["speed"]
            == terminal["details"]["gameEvent"]["result"]["simulationSpeed"])
    responses = [index[event_id] for event_id in failure["details"]["responseEvidenceIds"]]
    receipt = next(event for event in responses
                   if event["details"]["requestEvidenceId"] == request_event["eventId"])
    assert receipt["requestId"]
    assert receipt["commandId"] == terminal["commandId"]
    assert receipt["stateVersion"] == terminal["stateVersion"]
    assert receipt["details"]["responseEnvelope"]["requestId"] == receipt["requestId"]
    assert receipt["details"]["stepId"] == request_event["details"]["stepId"]
    assert failure["details"]["traceGaps"] == []
    linked_ids = (failure["details"]["requestEvidenceIds"]
                  + failure["details"]["responseEvidenceIds"]
                  + failure["details"]["gameEventEvidenceIds"])
    assert all(index[event_id]["details"]["caseId"] == case_id for event_id in linked_ids)
    case = next(event for event in events if event["eventType"] == "test_case"
                and event["name"] == case_id)
    assert case["status"] == "failed"
    assert case["details"]["failureEventIds"] == [event["eventId"] for event in failures]
    _assert_real_failure_formats(case, terminal, evidence_root, junit_path)


def _assert_real_failure_formats(
    case: dict, terminal: dict, evidence_root: Path, junit_path: Path,
) -> None:
    """JUnit can split call and teardown failures into two testcases; preserve both."""
    failed_xml = [item for item in ET.parse(junit_path).iter("testcase")
                  if item.get("name") == "test_controlled_real_failure"]
    assert any(item.find("failure") is not None for item in failed_xml)
    junit_failure_ids = set()
    junit_game_ids = set()
    for xml_case in failed_xml:
        properties = {item.get("name"): item.get("value")
                      for item in xml_case.findall("properties/property")}
        assert properties["caseId"] == case["name"]
        junit_failure_ids.update(json.loads(properties["failureEventIds"]))
        junit_game_ids.update(json.loads(properties["gameEventEvidenceIds"]))
    assert junit_failure_ids == set(case["details"]["failureEventIds"])
    assert junit_game_ids == set(case["details"]["gameEventEvidenceIds"])
    with sqlite3.connect(evidence_root / "phase2_evidence.sqlite3") as connection:
        row = connection.execute(
            "SELECT event_id,command_id,event_sequence,details_json FROM evidence_events "
            "WHERE event_id=?", (terminal["eventId"],),
        ).fetchone()
        counts = connection.execute(
            "SELECT status,total,passed,failed,skipped FROM runs",
        ).fetchone()
    assert row[:3] == (terminal["eventId"], terminal["commandId"], terminal["eventSequence"])
    assert json.loads(row[3])["gameEventId"] == terminal["details"]["gameEventId"]
    assert counts == ("failed", 2, 1, 1, 0)


def test_read_only_agent_save_validation_without_cleanup(  # pylint: disable=too-many-locals,too-many-statements
    tmp_path: Path, pytestconfig: pytest.Config, godot_executable: Path,
) -> None:
    """Exercise real read helpers, not restore transactions or mocked save outcomes.

    Direct helper calls deliberately do not test root configuration, full snapshot
    loading, lifecycle rollback or world retention. All generated files are retained.
    """
    game_root = Path(pytestconfig.rootpath).parent
    fixture_root = game_root / "tests/fixtures/historical_saves/beta6/agent_saves"
    snapshot_root = (fixture_root / "roundtrip-slot-beta6/sessions"
                     / "roundtrip-session-beta6/revisions/1")
    manifest_path = snapshot_root / "snapshot.json"
    source_manifest = json.loads(manifest_path.read_text("utf-8"))
    entry = source_manifest["residents"][0]
    source_payload = snapshot_root / entry["file"]
    source_paths = [manifest_path, source_payload,
                    game_root / "agent/lifecycle/AgentSaveStore.gd"]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in source_paths}
    assert before[str(source_payload)] == entry["sha256"]
    assert source_payload.stat().st_size == entry["byte_length"]
    truncated = tmp_path / "truncated-snapshot.json"
    truncated.write_text(manifest_path.read_text("utf-8")[:32], encoding="utf-8")
    non_object = tmp_path / "non-object-snapshot.json"
    non_object.write_text("[]", encoding="utf-8")
    incompatible = tmp_path / "incompatible-snapshot.json"
    future = {**source_manifest, "format_version": source_manifest["format_version"] + 1}
    incompatible.write_text(json.dumps(future, ensure_ascii=False), encoding="utf-8")
    context = {key: source_manifest[key] for key in
               ("slot_id", "session_id", "save_revision")}
    # GDScript parses JSON numeric fields as floats; context revision must be TYPE_INT.
    context_literal = json.dumps(context, ensure_ascii=False)
    script = tmp_path / "read-only-save-validation.gd"
    script.write_text(
        'extends SceneTree\n'
        'const Store = preload("res://agent/lifecycle/AgentSaveStore.gd")\n'
        'func _initialize() -> void:\n'
        '\tvar store = Store.new()\n'
        f'\tvar manifest = store._read_json({json.dumps(manifest_path.as_posix())})\n'
        f'\tvar context = {context_literal}\n'
        '\tvar entry = manifest["value"]["residents"][0]\n'
        f'\tvar root_path = {json.dumps(snapshot_root.as_posix())}\n'
        '\tvar cases = []\n'
        '\tcases.append({"id": "valid-json", "result": manifest})\n'
        f'\tcases.append({{"id": "truncated-json", "result": store._read_json('
        f'{json.dumps(truncated.as_posix())})}})\n'
        f'\tcases.append({{"id": "non-object-json", "result": store._read_json('
        f'{json.dumps(non_object.as_posix())})}})\n'
        '\tvar valid = store._read_checked_resident_payload(root_path, entry)\n'
        '\tvalid.erase("payload")\n'
        '\tcases.append({"id": "valid-payload", "result": valid})\n'
        '\tvar wrong_length = entry.duplicate(true)\n'
        '\twrong_length["byte_length"] += 1\n'
        '\tcases.append({"id": "wrong-length", "result": '
        'store._read_checked_resident_payload(root_path, wrong_length)})\n'
        '\tvar wrong_hash = entry.duplicate(true)\n'
        '\twrong_hash["sha256"] = "0".repeat(64)\n'
        '\tcases.append({"id": "wrong-hash", "result": '
        'store._read_checked_resident_payload(root_path, wrong_hash)})\n'
        f'\tvar future = store._read_json({json.dumps(incompatible.as_posix())})\n'
        '\tvar errors = store._snapshot_identity_errors(future["value"], context)\n'
        '\tcases.append({"id": "future-version", "result": '
        '{"ok": errors.is_empty(), "errors": errors}})\n'
        '\tprint("READ_ONLY_SAVE_RESULTS " + JSON.stringify(cases))\n'
        '\tquit(0)\n', encoding="utf-8",
    )
    started = time.monotonic()
    completed = subprocess.run(
        [str(godot_executable), "--headless", "--path", str(game_root),
         "--log-file", str(tmp_path / "godot-engine.log"),
         "--script", str(script)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=30, check=False,
        env={**environ, "AI_TOWN_PROVIDER_TEST_NO_NETWORK": "1"},
    )
    (tmp_path / "godot-output.log").write_text(completed.stdout + completed.stderr,
                                               encoding="utf-8")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "SCRIPT ERROR" not in completed.stdout + completed.stderr
    results = [line.removeprefix("READ_ONLY_SAVE_RESULTS ")
               for line in completed.stdout.splitlines()
               if line.startswith("READ_ONLY_SAVE_RESULTS ")]
    assert len(results) == 1, completed.stdout + completed.stderr
    cases = json.loads(results[0])
    expected = {
        "valid-json": (True, None), "truncated-json": (False, "存档文件损坏"),
        "non-object-json": (False, "存档文件损坏"), "valid-payload": (True, None),
        "wrong-length": (False, "byte_length 不一致"),
        "wrong-hash": (False, "SHA-256 不一致"),
        "future-version": (False, "format_version 不受支持"),
    }
    assert [item["id"] for item in cases] == list(expected)
    store = EvidenceStore(tmp_path / "evidence", "godot-read-only-save", metadata={
        "scope": "real read helpers only; NOT restore/rollback or path-guard acceptance",
        "sourceSha256": before, "historicalFixture": "beta6",
        "construction": "truncated JSON; non-object JSON; changed length/hash/version",
    })
    failures = []
    for item in cases:
        expected_ok, error_fragment = expected[item["id"]]
        result = item["result"]
        matches = result["ok"] is expected_ok and (error_fragment is None or
                    any(error_fragment in error for error in result.get("errors", [])))
        # Do not persist the full manifest or resident bytes; raw stdout remains local.
        store.record("save_validation", name=item["id"],
                     status="passed" if matches else "failed", details={
                         "expectedOk": expected_ok, "actualOk": result["ok"],
                         "errors": result.get("errors", []),
                         "scope": "read-helper-only",
                     })
        if not matches:
            failures.append(item)
    store.finish(status="failed" if failures else "passed", total=len(cases),
                 passed=len(cases) - len(failures), failed=len(failures), skipped=0,
                 other=0, duration_ms=round((time.monotonic() - started) * 1000, 3))
    assert not failures, failures
    assert before == {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in source_paths}


_SNAPSHOT_CASES = {
    "valid-full-15": None,
    "truncated-json": "存档文件损坏",
    "non-object-json": "存档文件损坏",
    "future-slot-version": "format_version 不受支持",
    "future-snapshot-version": "format_version 不受支持",
    "slot-identity": "slot_id 与上下文不一致",
    "session-identity": "session_id 与上下文不一致",
    "revision-identity": "save_revision 与上下文不一致",
    "missing-payload": "居民载荷缺失",
    "truncated-payload": "byte_length 不一致",
    "tampered-payload": "SHA-256 不一致",
    "duplicate-resident": "居民身份损坏或重复",
    "resident-set-mismatch": "居民集合与独立集合记录不一致",
    "independent-set-hash": "独立居民集合摘要不一致",
    "manifest-count": "居民集合数量不一致",
    "payload-path-escape": "居民文件引用无效",
    "valid-after-rejections": None,
}


def _file_fingerprints(root: Path) -> dict:
    """Include file names and bytes to detect mutations, additions and removals."""
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.rglob("*")) if path.is_file()}


@pytest.mark.parametrize("layout", ["same-root", "evidence-inside-temp", "existing-temp"])
def test_unsafe_basetemp_is_rejected_before_any_cleanup(tmp_path: Path, layout: str) -> None:
    """Reject unsafe pytest temp layouts before EvidenceStore or tmp_path can mutate them."""
    child_root = tmp_path / "safety-child"
    child_root.mkdir()
    suite_root = Path(__file__).resolve().parent
    shutil.copyfile(suite_root / "conftest.py", child_root / "conftest.py")
    child_test = child_root / "test_safety.py"
    child_test.write_text('def test_must_not_run(tmp_path):\n    assert False\n', encoding="utf-8")
    temp_root = child_root / "protected-temp"
    if layout == "existing-temp":
        temp_root.mkdir()
        (temp_root / "retained-failure.txt").write_text("keep original evidence", encoding="utf-8")
    before = _file_fingerprints(temp_root) if temp_root.exists() else None
    evidence_root = (temp_root if layout == "same-root" else temp_root / "evidence"
                     if layout == "evidence-inside-temp" else child_root / "evidence")
    completed = subprocess.run(
        [sys.executable, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
         "-c", str(suite_root.parent / "pytest.ini"), str(child_test),
         "--evidence-root", str(evidence_root), "--basetemp", str(temp_root),
         "--junitxml", str(child_root / "safety-junit.xml")],
        cwd=suite_root.parents[2], capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=30, check=False,
    )
    output = completed.stdout + completed.stderr
    (child_root / "child-output.log").write_text(output, encoding="utf-8")
    assert completed.returncode == 4, output
    expected = ("Refusing existing basetemp" if layout == "existing-temp" else
                "Evidence root must not equal or lie inside basetemp")
    assert expected in output
    assert not evidence_root.exists(), "Rejected layout must not create an evidence store"
    assert before == (_file_fingerprints(temp_root) if temp_root.exists() else None)


def _construct_snapshot_case(  # pylint: disable=too-many-branches,too-many-locals
    destination: Path, source_slot: Path, manifest: dict, case_id: str,
) -> dict:
    """Construct retained copies; a missing payload is omitted, never deleted."""
    copied = json.loads(json.dumps(manifest))
    slot = json.loads((source_slot / "slot.json").read_text("utf-8"))
    source_revision = (source_slot / "sessions" / manifest["session_id"]
                       / "revisions" / str(manifest["save_revision"]))
    revision = (destination / manifest["slot_id"] / "sessions" / manifest["session_id"]
                / "revisions" / str(manifest["save_revision"]))
    revision.mkdir(parents=True)
    resident_set = json.loads((source_revision / "resident_set.json").read_text("utf-8"))
    for index, entry in enumerate(manifest["residents"]):
        # Fixture paths must be plain file names, not traversal or symlinks.
        assert Path(entry["file"]).name == entry["file"]
        source_payload = source_revision / entry["file"]
        assert not source_payload.is_symlink()
        payload = source_payload.read_bytes()
        assert len(payload) == entry["byte_length"]
        assert hashlib.sha256(payload).hexdigest() == entry["sha256"]
        if index == 0:
            if case_id == "missing-payload":
                continue
            if case_id == "truncated-payload":
                payload = payload[:-1]
            if case_id == "tampered-payload":
                payload = bytes([payload[0] ^ 1]) + payload[1:]
        (revision / entry["file"]).write_bytes(payload)
    if case_id == "future-slot-version":
        slot["format_version"] += 1
    elif case_id == "future-snapshot-version":
        copied["format_version"] += 1
    elif case_id == "slot-identity":
        slot["slot_id"] = "different-slot"
    elif case_id == "session-identity":
        copied["session_id"] = "different-session"
    elif case_id == "revision-identity":
        copied["save_revision"] += 1
    elif case_id == "duplicate-resident":
        copied["residents"][1]["resident_id"] = copied["residents"][0]["resident_id"]
    elif case_id == "resident-set-mismatch":
        copied["residents"][-1]["resident_id"] = "resident_zz_test"
    elif case_id == "independent-set-hash":
        resident_set["resident_set_sha256"] = "0" * 64
    elif case_id == "manifest-count":
        copied["resident_count"] -= 1
    elif case_id == "payload-path-escape":
        copied["residents"][0]["file"] = "../resident_0000.bin"
    snapshot_text = json.dumps(copied, ensure_ascii=False)
    if case_id == "truncated-json":
        snapshot_text = snapshot_text[:32]
    elif case_id == "non-object-json":
        snapshot_text = "[]"
    (revision / "snapshot.json").write_text(snapshot_text, encoding="utf-8")
    (revision / "resident_set.json").write_text(
        json.dumps(resident_set, ensure_ascii=False), encoding="utf-8")
    (destination / manifest["slot_id"] / "slot.json").write_text(
        json.dumps(slot, ensure_ascii=False), encoding="utf-8")
    return {"id": case_id, "root": destination.as_posix(), "context": {
        key: manifest[key] for key in ("slot_id", "session_id", "save_revision")}}


def _write_snapshot_reader(script: Path, specs_path: Path) -> None:
    """Bind only the storage path; run the unmodified real loader and hash returned bytes."""
    script.write_text(
        'extends SceneTree\n'
        'const Store = preload("res://agent/lifecycle/AgentSaveStore.gd")\n'
        'func _initialize() -> void:\n'
        f'\tvar specs = JSON.parse_string(FileAccess.get_file_as_string('
        f'{json.dumps(specs_path.as_posix())}))\n'
        '\tvar cases = []\n'
        '\tfor spec in specs:\n'
        '\t\tvar store = Store.new()\n'
        '\t\tstore.set("_store_root", spec["root"])\n'
        '\t\tvar context = spec["context"]\n'
        '\t\tcontext["save_revision"] = int(context["save_revision"])\n'
        '\t\tvar started = Time.get_ticks_usec()\n'
        '\t\tvar result = store.load_snapshot(context)\n'
        '\t\tvar payloads = []\n'
        '\t\tfor resident_id in result.get("resident_payloads", {}):\n'
        '\t\t\tvar entry = result["resident_payloads"][resident_id]\n'
        '\t\t\tvar hashing = HashingContext.new()\n'
        '\t\t\thashing.start(HashingContext.HASH_SHA256)\n'
        '\t\t\thashing.update(entry["payload"])\n'
        '\t\t\tpayloads.append({"residentId": resident_id,\n'
        '\t\t\t\t"residentName": entry["resident_name"],\n'
        '\t\t\t\t"byteLength": entry["payload"].size(),\n'
        '\t\t\t\t"sha256": hashing.finish().hex_encode()})\n'
        '\t\tcases.append({"id": spec["id"], "ok": result.get("ok"),\n'
        '\t\t\t"errors": result.get("errors", []),\n'
        '\t\t\t"context": result.get("context"), "payloads": payloads,\n'
        '\t\t\t"durationMs": (Time.get_ticks_usec() - started) / 1000.0})\n'
        '\tprint("FULL_READ_ONLY_SAVE_RESULTS " + JSON.stringify(cases))\n'
        '\tquit(0)\n', encoding="utf-8")


def test_real_load_snapshot_read_only_with_retained_abnormal_copies(  # pylint: disable=too-many-locals,too-many-statements
    tmp_path: Path, pytestconfig: pytest.Config, godot_executable: Path,
) -> None:
    """Full read-only Store entry; NOT hydration, rollback, cleanup or root-guard acceptance."""
    game_root = Path(pytestconfig.rootpath).parent
    source_slot = (game_root / "tests/fixtures/historical_saves/beta6/agent_saves"
                   / "roundtrip-slot-beta6")
    source_revision = source_slot / "sessions/roundtrip-session-beta6/revisions/1"
    manifest = json.loads((source_revision / "snapshot.json").read_text("utf-8"))
    assert len(manifest["residents"]) == 15
    source_before = _file_fingerprints(source_slot)
    loader_path = game_root / "agent/lifecycle/AgentSaveStore.gd"
    loader_before = hashlib.sha256(loader_path.read_bytes()).hexdigest()
    fixtures = tmp_path / "fixtures"
    specs = [_construct_snapshot_case(fixtures / case_id, source_slot, manifest, case_id)
             for case_id in _SNAPSHOT_CASES]
    fixtures_before = _file_fingerprints(fixtures)
    specs_path = tmp_path / "snapshot-cases.json"
    specs_path.write_text(json.dumps(specs, ensure_ascii=False), encoding="utf-8")
    script = tmp_path / "full-read-only-save-validation.gd"
    _write_snapshot_reader(script, specs_path)
    started = time.monotonic()
    output_path = tmp_path / "godot-output.log"
    try:
        completed = subprocess.run(
            [str(godot_executable), "--headless", "--path", str(game_root),
             "--log-file", str(tmp_path / "godot-engine.log"), "--script", str(script)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=45, check=False,
            env={**environ, "AI_TOWN_PROVIDER_TEST_NO_NETWORK": "1"},
        )
    except subprocess.TimeoutExpired as error:
        partial = b"".join(part.encode("utf-8") if isinstance(part, str) else part or b""
                           for part in (error.stdout, error.stderr))
        output_path.write_bytes(partial)
        raise
    output = completed.stdout + completed.stderr
    output_path.write_text(output, encoding="utf-8")
    assert completed.returncode == 0, output
    assert "SCRIPT ERROR" not in output, output
    result_lines = [line.removeprefix("FULL_READ_ONLY_SAVE_RESULTS ")
                    for line in completed.stdout.splitlines()
                    if line.startswith("FULL_READ_ONLY_SAVE_RESULTS ")]
    assert len(result_lines) == 1, output
    cases = json.loads(result_lines[0])
    (tmp_path / "snapshot-results.json").write_text(
        json.dumps(cases, ensure_ascii=False, indent=2), encoding="utf-8")
    assert [case["id"] for case in cases] == list(_SNAPSHOT_CASES)
    expected_payloads = {entry["resident_id"]: {
        "residentId": entry["resident_id"], "residentName": entry["resident_name"],
        "byteLength": entry["byte_length"], "sha256": entry["sha256"],
    } for entry in manifest["residents"]}
    evidence = EvidenceStore(tmp_path / "evidence", "godot-full-read-only-save", metadata={
        "scope": "real load_snapshot; NOT hydration/rollback/cleanup/root-guard acceptance",
        "storageBinding": "private _store_root bound to retained absolute fixture copy",
        "loaderSha256": loader_before, "sourceSha256": source_before,
        "construction": "snapshot-cases.json and retained fixtures; no deletion",
        "network": "approved AI_TOWN_PROVIDER_TEST_NO_NETWORK=1 on Godot child only",
    })
    failures = []
    expected_context = specs[0]["context"]
    for case in cases:
        fragment = _SNAPSHOT_CASES[case["id"]]
        actual_payloads = {item["residentId"]: item for item in case["payloads"]}
        if fragment is None:
            matches = (case["ok"] is True and not case["errors"]
                       and case["context"] == expected_context
                       and len(case["payloads"]) == 15 and actual_payloads == expected_payloads)
        else:
            matches = (case["ok"] is False and not case["payloads"]
                       and case["context"] is None
                       and any(fragment in error for error in case["errors"]))
        evidence.record("save_validation", name=case["id"],
                        status="passed" if matches else "failed",
                        duration_ms=case["durationMs"], details={
                            "expectedOk": fragment is None, "expectedErrorFragment": fragment,
                            "actual": case, "fixtureRoot": (fixtures / case["id"]).as_posix(),
                            "outputPath": output_path.as_posix(),
                            "scope": "full-store-read-only; no game events or HTTP requests",
                        })
        if not matches:
            failures.append(case)
    unchanged = (source_before == _file_fingerprints(source_slot)
                 and fixtures_before == _file_fingerprints(fixtures)
                 and loader_before == hashlib.sha256(loader_path.read_bytes()).hexdigest())
    evidence.record("isolation_check", name="source-loader-and-fixtures-unchanged",
                    status="passed" if unchanged else "failed",
                    details={"fixtureSha256Before": fixtures_before,
                             "fixtureSha256After": _file_fingerprints(fixtures)})
    failure_count = len(failures) + int(not unchanged)
    evidence.finish(status="failed" if failure_count else "passed", total=len(cases) + 1,
                    passed=len(cases) + 1 - failure_count, failed=failure_count,
                    skipped=0, other=0,
                    duration_ms=round((time.monotonic() - started) * 1000, 3))
    assert not failures, failures
    assert unchanged, "Read-only validation changed source, loader or retained fixtures"
