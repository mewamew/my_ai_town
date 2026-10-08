"""External write-command regression against the isolated GameTestBridge."""

from __future__ import annotations

import json
import time
import uuid
from pathlib import Path
from typing import Callable

import pytest
import requests
from jsonschema import Draft202012Validator, FormatChecker


pytestmark = [pytest.mark.live_bridge, pytest.mark.command_bridge]
ResponseRecorder = Callable[[str, requests.Response, int], None]
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "protocol.schema.json"
with SCHEMA_PATH.open("r", encoding="utf-8") as _schema_handle:
    RESPONSE_VALIDATOR = Draft202012Validator(
        json.load(_schema_handle),
        format_checker=FormatChecker(),
    )


def _json_request(  # pylint: disable=too-many-arguments
    session: requests.Session,
    recorder: ResponseRecorder,
    method: str,
    base_url: str,
    path: str,
    expected_status: int,
    *,
    payload: dict | None = None,
) -> dict:
    response = session.request(
        method,
        f"{base_url}{path}",
        json=payload,
        timeout=5.0,
    )
    recorder(f"{method} {path}", response, expected_status)
    assert response.status_code == expected_status, response.text
    assert response.headers["Content-Type"].startswith("application/json")
    body = response.json()
    RESPONSE_VALIDATOR.validate(body)
    return body


def _world(
    session: requests.Session,
    recorder: ResponseRecorder,
    base_url: str,
) -> dict:
    return _json_request(
        session,
        recorder,
        "GET",
        base_url,
        "/world/state",
        200,
    )["data"]


def _command(snapshot: dict, *, timeout_ms: int = 3000) -> dict:
    identifier = f"pytest-{uuid.uuid4().hex}"
    return {
        "commandId": identifier,
        "idempotencyKey": identifier,
        "expectedSessionId": snapshot["sessionId"],
        "expectedWorldGeneration": snapshot["worldGeneration"],
        "expectedStateVersion": snapshot["stateVersion"],
        "timeoutMs": timeout_ms,
    }


def _poll_command(
    session: requests.Session,
    recorder: ResponseRecorder,
    base_url: str,
    command_id: str,
    *,
    timeout_seconds: float = 10.0,
) -> dict:
    deadline = time.monotonic() + timeout_seconds
    latest: dict = {}
    while time.monotonic() < deadline:
        latest = _json_request(
            session,
            recorder,
            "GET",
            base_url,
            f"/commands/{command_id}",
            200,
        )["data"]
        if latest["status"] in {"completed", "failed"}:
            return latest
        time.sleep(0.05)
    pytest.fail(f"command {command_id} did not finish: {latest}", pytrace=False)


def test_set_speed_succeeds_and_replay_is_idempotent(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
) -> None:
    """A lost-response retry must return the original receipt without a second mutation."""
    health = _json_request(
        http_session,
        record_bridge_response,
        "GET",
        command_bridge_base_url,
        "/health",
        200,
    )
    assert health["data"]["readOnly"] is False
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    target_speed = 2 if before["simulationSpeed"] != 2 else 3
    command = {**_command(before), "speed": target_speed}

    first = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        200,
        payload=command,
    )
    assert first["data"]["accepted"] is True
    assert first["data"]["status"] == "completed"
    assert first["data"]["result"] == {
        "simulationSpeed": target_speed,
        "changed": True,
    }
    assert first["data"]["stateVersion"] == before["stateVersion"] + 1

    replay = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        200,
        payload=command,
    )
    assert replay["requestId"] != first["requestId"]
    assert replay["data"] == first["data"]

    queried = _json_request(
        http_session,
        record_bridge_response,
        "GET",
        command_bridge_base_url,
        f"/commands/{command['commandId']}",
        200,
    )
    assert queried["data"] == first["data"]
    after = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after["simulationSpeed"] == target_speed
    assert after["stateVersion"] == first["data"]["stateVersion"]


def test_command_identity_conflicts_do_not_add_side_effects(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
) -> None:
    """Reusing either identity for changed work must be rejected."""
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    target_speed = 2 if before["simulationSpeed"] != 2 else 3
    command = {**_command(before), "speed": target_speed}
    accepted = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        200,
        payload=command,
    )

    changed_work = {**command, "speed": 1 if target_speed != 1 else 3}
    idempotency_conflict = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        409,
        payload=changed_work,
    )
    assert idempotency_conflict["error"]["code"] == "IDEMPOTENCY_CONFLICT"

    command_id_conflict = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        409,
        payload={**command, "idempotencyKey": f"other-{uuid.uuid4().hex}"},
    )
    assert command_id_conflict["error"]["code"] == "COMMAND_ID_CONFLICT"
    after = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after["simulationSpeed"] == target_speed
    assert after["stateVersion"] == accepted["data"]["stateVersion"]


def test_stale_version_and_invalid_schema_are_side_effect_free(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
) -> None:
    """State races and malformed commands must not mutate the World."""
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    target_speed = 2 if before["simulationSpeed"] != 2 else 3
    stale = {
        **_command(before),
        "expectedStateVersion": before["stateVersion"] + 1,
        "speed": target_speed,
    }
    stale_response = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        409,
        payload=stale,
    )
    assert stale_response["error"]["code"] == "STATE_VERSION_CONFLICT"

    invalid = {**_command(before), "speed": 4}
    invalid_response = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        400,
        payload=invalid,
    )
    assert invalid_response["error"]["code"] == "INVALID_COMMAND_SCHEMA"

    missing = _command(before)
    missing_response = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/set-speed",
        400,
        payload=missing,
    )
    assert missing_response["error"]["code"] == "INVALID_COMMAND_SCHEMA"
    after = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after["simulationSpeed"] == before["simulationSpeed"]
    assert after["stateVersion"] == before["stateVersion"]


def test_save_and_load_reach_terminal_state_and_replay_safely(  # pylint: disable=too-many-locals
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
) -> None:
    """External clients must distinguish acceptance, completion, and restored generation."""
    before_save = _world(http_session, record_bridge_response, command_bridge_base_url)
    save_command = _command(before_save, timeout_ms=10000)
    save_accepted = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/save",
        202,
        payload=save_command,
    )
    assert save_accepted["data"]["status"] == "running"

    concurrent = _command(before_save, timeout_ms=10000)
    busy = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/save",
        409,
        payload=concurrent,
    )
    assert busy["error"]["code"] == "SESSION_COMMAND_BUSY"

    saved = _poll_command(
        http_session,
        record_bridge_response,
        command_bridge_base_url,
        save_command["commandId"],
    )
    assert saved["status"] == "completed"
    assert saved["result"]["saveRevision"] == 7
    save_replay = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/save",
        200,
        payload=save_command,
    )
    assert save_replay["data"] == saved

    before_load = _world(http_session, record_bridge_response, command_bridge_base_url)
    load_command = _command(before_load, timeout_ms=10000)
    load_accepted = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/load",
        202,
        payload=load_command,
    )
    assert load_accepted["data"]["status"] == "running"
    loaded = _poll_command(
        http_session,
        record_bridge_response,
        command_bridge_base_url,
        load_command["commandId"],
    )
    assert loaded["status"] == "completed"
    assert loaded["result"]["saveRevision"] == 7
    after_load = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after_load["residentCount"] == 15
    assert after_load["worldGeneration"] != before_load["worldGeneration"]

    load_replay = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/load",
        200,
        payload=load_command,
    )
    assert load_replay["data"] == loaded


def test_move_rejection_is_structured_without_a_player_runtime(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
) -> None:
    """The lightweight command fixture must reject movement rather than fake success."""
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    avatar = before["playerAvatar"]
    movement = {
        **_command(before, timeout_ms=1000),
        "spaceId": avatar["spaceId"] or "town_outdoor",
        "targetPosition": [avatar["position"][0] + 64, avatar["position"][1]],
        "tolerance": 6,
    }
    rejected = _json_request(
        http_session,
        record_bridge_response,
        "POST",
        command_bridge_base_url,
        "/commands/move-player",
        503,
        payload=movement,
    )
    assert rejected["error"]["code"] == "PLAYER_RUNTIME_NOT_READY"
    after = _world(http_session, record_bridge_response, command_bridge_base_url)
    assert after["stateVersion"] == before["stateVersion"]


def test_real_command_event_links_request_receipt_and_generation(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
    bridge_event_trace,
) -> None:
    """Observe a real speed mutation, not a mocked protocol event or save result."""
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    speed = 2 if before["simulationSpeed"] != 2 else 3
    command = {**_command(before), "speed": speed}
    receipt = _json_request(http_session, record_bridge_response, "POST",
                            command_bridge_base_url, "/commands/set-speed", 200,
                            payload=command)
    observed = bridge_event_trace.wait_for_command(command["commandId"])
    source = observed["details"]["gameEvent"]
    assert source["eventType"] == "command-completed"
    assert source["commandId"] == receipt["data"]["commandId"]
    assert source["worldGeneration"] == before["worldGeneration"]
    assert source["stateVersion"] == receipt["data"]["stateVersion"]
    assert source["result"] == receipt["data"]["result"]
    assert observed["eventSequence"] == source["eventSequence"] > 0
    assert observed["eventId"] != source["eventId"]
    assert observed["details"]["relatedRequestEvidenceIds"]
    assert observed["details"]["relatedResponseEvidenceIds"]
    assert "failure" in source
    assert source["failure"] is None


def test_idle_event_stream_does_not_resend_last_frame(
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
    bridge_event_trace,
) -> None:
    """Observe the wire after a real command, without filtering repeated frames."""
    before = _world(http_session, record_bridge_response, command_bridge_base_url)
    command = {**_command(before), "speed": 2 if before["simulationSpeed"] != 2 else 3}
    _json_request(http_session, record_bridge_response, "POST", command_bridge_base_url,
                  "/commands/set-speed", 200, payload=command)
    bridge_event_trace.wait_for_command(command["commandId"])
    bridge_event_trace.flush(0.3)
    observations = bridge_event_trace.game_events
    source_ids = [event["details"]["gameEventId"] for event in observations]
    sequences = [event["eventSequence"] for event in observations]
    assert len(source_ids) >= 2, "command and state-change events must both be observed"
    assert len(source_ids) == len(set(source_ids)), observations
    assert all(current > previous for previous, current in
               zip(sequences, sequences[1:])), observations


def test_captured_event_disorder_duplicate_and_gap_resync_read_only(  # pylint: disable=too-many-locals,too-many-statements
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
    bridge_event_trace,
) -> None:
    """Controlled replay of real events; not a claim of automatic runtime recovery."""
    before_cursor = _json_request(http_session, record_bridge_response, "GET",
                                  command_bridge_base_url, "/events/cursor", 200)["data"]
    cursor_evidence_ids = [bridge_event_trace.responses[-1]["eventId"]]
    terminal = None
    for _ in range(2):
        before = _world(http_session, record_bridge_response, command_bridge_base_url)
        command = {**_command(before), "speed": 2 if before["simulationSpeed"] != 2 else 3}
        _json_request(http_session, record_bridge_response, "POST", command_bridge_base_url,
                      "/commands/set-speed", 200, payload=command)
        terminal = bridge_event_trace.wait_for_command(command["commandId"])
        bridge_event_trace.flush(0.1)
    assert terminal is not None
    after_cursor = _json_request(http_session, record_bridge_response, "GET",
                                 command_bridge_base_url, "/events/cursor", 200)["data"]
    cursor_evidence_ids.append(bridge_event_trace.responses[-1]["eventId"])
    sources = list(bridge_event_trace.game_events)
    assert len(sources) >= 4, "Two real mutations must yield command and state-change events"
    original = json.dumps(sources, sort_keys=True)
    count = len(sources)
    scenarios = {
        "ordered-control": (list(range(count)), set()),
        "reversed-order": (list(reversed(range(count))),
                           {"non-increasing-game-event-sequence"}),
        "duplicate-terminal": (list(range(count)) + [count - 1],
                               {"duplicate-game-event-id", "non-increasing-game-event-sequence"}),
        "omitted-middle-event": ([0, *range(2, count)], {"game-event-sequence-gap"}),
        "omitted-first-terminal": (list(range(1, count)), set()),
        "omitted-last-state-notification": (list(range(count - 1)), set()),
        "omitted-last-terminal-window": (list(range(count - 2)), set()),
        "omitted-all-events": ([], set()),
    }
    baseline = _world(http_session, record_bridge_response, command_bridge_base_url)
    request_count = len(bridge_event_trace.requests)
    live_count = len(bridge_event_trace.game_events)
    command_id = terminal["commandId"]
    for scenario, (order, expected_anomalies) in scenarios.items():
        replay = bridge_event_trace.replay_observations(scenario, sources, order)
        after = _world(http_session, record_bridge_response, command_bridge_base_url)
        receipt = _json_request(http_session, record_bridge_response, "GET",
                                command_bridge_base_url, f"/commands/{command_id}", 200)["data"]
        # Record facts before assertions, so any failure retains the full controlled timeline.
        checkpoint = bridge_event_trace.replay_checkpoint(scenario, replay, {
            "beforeState": baseline, "afterState": after, "actualReceipt": receipt,
            "beforeCursor": before_cursor, "afterCursor": after_cursor,
            "cursorResponseEvidenceIds": cursor_evidence_ids,
        })
        anomalies = {item for event in replay for item in event["details"]["sequenceObservations"]}
        assert anomalies == expected_anomalies, replay
        expected_commands = {event["commandId"] for event in sources
                             if event["name"] == "command-completed"}
        assert set(checkpoint["details"]["expectedTerminalCommandIds"]) == expected_commands
        expected_missing = ({sources[0]["commandId"]} if scenario == "omitted-first-terminal"
                            else {sources[-2]["commandId"]}
                            if scenario == "omitted-last-terminal-window"
                            else expected_commands if scenario == "omitted-all-events" else set())
        assert set(checkpoint["details"]["missingTerminalCommandIds"]) == expected_missing
        assert checkpoint["details"]["allFramesComplete"] is (scenario == "ordered-control")
        assert checkpoint["details"]["completenessBlindSpot"] is None
        window = checkpoint["details"]["eventWindow"]
        expected_sequences = set(range(before_cursor["lastEmittedEventSequence"] + 1,
                                       after_cursor["lastEmittedEventSequence"] + 1))
        assert set(window["missingEventSequences"]) == expected_sequences - {
            event["eventSequence"] for event in replay}
        assert not window["foreignEventIds"]
        assert [event["details"]["sourceEvidenceId"] for event in replay] == [
            sources[index]["eventId"] for index in order]
        for event, source_index in zip(replay, order):
            source = sources[source_index]
            assert event["eventType"] == "controlled_event_replay"
            assert event["details"]["observationSource"] == "controlled-replay"
            assert event["details"]["gameEvent"] == source["details"]["gameEvent"]
            assert event["details"]["wirePayloadSha256"] == source["details"]["wirePayloadSha256"]
            assert event["details"]["receiveIndex"] == source["details"]["receiveIndex"]
            assert event["eventSequence"] == source["eventSequence"]
            assert event["eventId"] != source["eventId"]
            assert event["eventId"] != source["details"]["gameEventId"]
            assert not event["details"]["schemaErrors"]
        assert (after["sessionId"], after["worldGeneration"], after["stateVersion"],
                after["simulationSpeed"], after["residentCount"]) == (
                    baseline["sessionId"], baseline["worldGeneration"], baseline["stateVersion"],
                    baseline["simulationSpeed"], 15)
        assert receipt["commandId"] == command_id
        assert receipt["status"] == "completed"
        assert receipt["result"] == terminal["details"]["gameEvent"]["result"]
        assert receipt["stateVersion"] == terminal["stateVersion"] == after["stateVersion"]
    assert json.dumps(sources, sort_keys=True) == original
    assert len(bridge_event_trace.game_events) == live_count
    resync_requests = bridge_event_trace.requests[request_count:]
    assert len(resync_requests) == 16
    assert all(event["name"].startswith("GET ") for event in resync_requests)


@pytest.mark.parametrize("disconnect_mode", ["client-close", "server-policy-close"])
def test_real_disconnect_reconnect_preserves_receipt_and_reclaims_slots(  # pylint: disable=too-many-locals,too-many-statements
    disconnect_mode: str,
    http_session: requests.Session,
    command_bridge_base_url: str,
    record_bridge_response: ResponseRecorder,
    bridge_event_trace,
) -> None:
    """Real TCP/WS gaps never justify reposting a completed command or faking replay."""
    trace = bridge_event_trace
    trace.resource_checkpoint(f"{disconnect_mode}-baseline")
    baseline = _world(http_session, record_bridge_response, command_bridge_base_url)
    command = {**_command(baseline), "speed": 2 if baseline["simulationSpeed"] != 2 else 3}
    _json_request(http_session, record_bridge_response, "POST", command_bridge_base_url,
                  "/commands/set-speed", 200, payload=command)
    previous_event = trace.wait_for_command(command["commandId"])
    trace.flush(0.1)
    baseline_sequence = trace.game_events[-1]["eventSequence"]
    for cycle in range(1, 4):
        before = _world(http_session, record_bridge_response, command_bridge_base_url)
        old_connection = trace.stream.connection_id
        trace.disconnect(disconnect_mode)
        if cycle == 1:
            trace.resource_checkpoint(f"{disconnect_mode}-disconnected")
        live_count = len(trace.game_events)
        request_start = len(trace.requests)
        offline = {**_command(before), "speed": 2 if before["simulationSpeed"] != 2 else 3}
        posted = _json_request(http_session, record_bridge_response, "POST",
                               command_bridge_base_url, "/commands/set-speed", 200,
                               payload=offline)["data"]
        queried = _poll_command(http_session, record_bridge_response, command_bridge_base_url,
                                offline["commandId"])
        offline_state = _world(http_session, record_bridge_response, command_bridge_base_url)
        trace.connection_checkpoint(f"{disconnect_mode}-{cycle}-offline", {
            "beforeState": before, "afterState": offline_state,
            "postedReceipt": posted, "queriedReceipt": queried,
            "disconnectedCommandId": offline["commandId"],
            "noObservedEventMeaning": "subscription closed; not business command failure",
        })
        assert posted == queried and queried["status"] == "completed"
        assert queried["commandId"] == offline["commandId"]
        assert offline_state["stateVersion"] == before["stateVersion"] + 1
        assert offline_state["simulationSpeed"] == offline["speed"]
        assert len(trace.game_events) == live_count
        trace.reconnect()
        trace.flush(0.1)
        assert trace.stream.connection_id != old_connection
        assert len(trace.game_events) == live_count, "Bridge must not invent history replay"
        resync_state = _world(http_session, record_bridge_response, command_bridge_base_url)
        resync_receipt = _json_request(http_session, record_bridge_response, "GET",
                                      command_bridge_base_url,
                                      f"/commands/{offline['commandId']}", 200)["data"]
        trace.connection_checkpoint(f"{disconnect_mode}-{cycle}-resync", {
            "beforeState": offline_state, "afterState": resync_state,
            "queriedReceipt": resync_receipt, "disconnectedCommandId": offline["commandId"],
            "previousConnectionId": old_connection,
        })
        assert resync_receipt == queried
        for field in ("sessionId", "worldGeneration", "stateVersion", "simulationSpeed",
                      "residentCount"):
            assert resync_state[field] == offline_state[field]
        assert resync_state["residentCount"] == 15
        recovery_requests = trace.requests[request_start:]
        assert sum(event["name"].startswith("POST ") for event in recovery_requests) == 1
        assert all(event["name"].startswith("GET ") for event in recovery_requests[1:])
        fresh = {**_command(resync_state),
                 "speed": 2 if resync_state["simulationSpeed"] != 2 else 3}
        fresh_receipt = _json_request(http_session, record_bridge_response, "POST",
                                     command_bridge_base_url, "/commands/set-speed", 200,
                                     payload=fresh)["data"]
        previous_event = trace.wait_for_command(fresh["commandId"])
        trace.flush(0.1)
        source = previous_event["details"]["gameEvent"]
        assert source["eventType"] == "command-completed"
        assert source["commandId"] == fresh_receipt["commandId"]
        assert source["stateVersion"] == fresh_receipt["stateVersion"]
        assert source["worldGeneration"] == resync_state["worldGeneration"]
        assert previous_event["details"]["connectionId"] == trace.stream.connection_id
        assert previous_event["eventSequence"] > baseline_sequence + 1
        assert previous_event["details"]["relatedRequestEvidenceIds"]
        assert previous_event["details"]["relatedResponseEvidenceIds"]
        assert previous_event["eventId"] != source["eventId"]
        assert not any(event["commandId"] == offline["commandId"] for event in trace.game_events)
        baseline_sequence = trace.game_events[-1]["eventSequence"]
        _json_request(http_session, record_bridge_response, "GET", command_bridge_base_url,
                      "/health", 200)
    # More cumulative subscriptions than MAX_CLIENTS=8, serial, NOT concurrent load.
    churn_before = _world(http_session, record_bridge_response, command_bridge_base_url)
    for _ in range(9):
        trace.disconnect(disconnect_mode)
        trace.reconnect()
        _json_request(http_session, record_bridge_response, "GET", command_bridge_base_url,
                      "/health", 200)
    churn_after = _world(http_session, record_bridge_response, command_bridge_base_url)
    trace.connection_checkpoint(f"{disconnect_mode}-serial-slot-reuse", {
        "beforeState": churn_before, "afterState": churn_after,
        "serialSubscriptionCycles": 9, "serverMaxClients": 8,
        "scopeLimit": "slot reuse and reader cleanup, NOT proof of no memory leak",
    })
    trace.resource_checkpoint(f"{disconnect_mode}-after-churn")
    for field in ("sessionId", "worldGeneration", "stateVersion", "simulationSpeed",
                  "residentCount"):
        assert churn_after[field] == churn_before[field]
    assert len(set(trace.connection_history)) == len(trace.connection_history) == 13
    source_ids = [event["details"]["gameEventId"] for event in trace.game_events]
    sequences = [event["eventSequence"] for event in trace.game_events]
    assert len(source_ids) == len(set(source_ids))
    assert all(current > previous for previous, current in zip(sequences, sequences[1:]))
    assert not trace.gaps and not trace.protocol_errors
