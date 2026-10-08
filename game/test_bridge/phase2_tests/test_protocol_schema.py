"""JSON Schema contract and boundary tests for GameTestBridge v0.1."""

from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker, ValidationError


SCHEMA_PATH = Path(__file__).resolve().parents[1] / "protocol.schema.json"


@pytest.fixture(scope="module", name="protocol_schema")
def fixture_protocol_schema() -> dict:
    """Load the checked-in protocol schema without mutating it."""
    with SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _definition_validator(schema: dict, definition: str) -> Draft202012Validator:
    wrapper = {
        "$schema": schema["$schema"],
        "$ref": f"#/$defs/{definition}",
        "$defs": schema["$defs"],
    }
    return Draft202012Validator(wrapper, format_checker=FormatChecker())


def test_protocol_schema_is_valid_draft_2020_12(protocol_schema: dict) -> None:
    """The full document must itself be a valid Draft 2020-12 schema."""
    Draft202012Validator.check_schema(protocol_schema)


@pytest.mark.parametrize(("field", "value"), [
    ("lastEmittedEventSequence", -1), ("lastEmittedEventSequence", 1.5),
    ("lastEmittedEventSequence", True), ("streamId", "wrong-stream"),
    ("delivered", True),
])
def test_event_cursor_rejects_invalid_contract(protocol_schema: dict, field: str,
                                              value: object) -> None:
    """Synthetic schema-only negatives are not game observation evidence."""
    cursor = {"sessionId": "test", "worldGeneration": "generation:1", "stateVersion": 1,
              "capturedAt": "2026-10-05T07:00:00Z", "streamId": "a" * 24,
              "lastEmittedEventSequence": 0}
    validator = _definition_validator(protocol_schema, "eventCursor")
    validator.validate(cursor)
    cursor[field] = value
    with pytest.raises(ValidationError):
        validator.validate(cursor)


@pytest.mark.parametrize(("stream", "end", "expected"), [
    ("b" * 24, 2, None), ("a" * 24, 1, None),
    ("a" * 24, 5000, None), ("a" * 24, 2, True),
])
def test_event_window_guard_contract(event_window_audit, stream: str, end: int,
                                     expected: bool | None) -> None:
    """Synthetic unit inputs test the audit guard, not actual game observations."""
    before = {"streamId": "a" * 24, "worldGeneration": "generation:1",
              "lastEmittedEventSequence": 2}
    after = {**before, "streamId": stream, "lastEmittedEventSequence": end}
    result = event_window_audit(before, after, [])
    assert result["allFramesComplete"] is expected
    if expected is None:
        assert result["completenessBlindSpot"]
    else:
        assert result["missingEventSequences"] == []
        assert result["completenessBlindSpot"] is None


def test_set_speed_request_accepts_valid_contract(protocol_schema: dict) -> None:
    """A complete speed command at legal boundaries must validate."""
    request_body = {
        "commandId": "phase2-speed-001",
        "idempotencyKey": "phase2-speed-key-001",
        "expectedSessionId": "bridge-offline-fixture",
        "expectedWorldGeneration": "generation:1",
        "expectedStateVersion": 7,
        "timeoutMs": 3000,
        "speed": 2,
    }
    _definition_validator(protocol_schema, "setSpeedRequest").validate(request_body)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("speed", 4),
        ("timeoutMs", 0),
        ("expectedStateVersion", -1),
        ("commandId", "contains spaces"),
    ],
)
def test_set_speed_request_rejects_invalid_boundaries(
    protocol_schema: dict, field: str, value: object
) -> None:
    """Illegal speed, timeout, revision, and identifier values must fail."""
    request_body = {
        "commandId": "phase2-speed-002",
        "idempotencyKey": "phase2-speed-key-002",
        "expectedSessionId": "bridge-offline-fixture",
        "expectedWorldGeneration": "generation:1",
        "expectedStateVersion": 7,
        "timeoutMs": 3000,
        "speed": 2,
    }
    invalid_body = copy.deepcopy(request_body)
    invalid_body[field] = value
    with pytest.raises(ValidationError):
        _definition_validator(protocol_schema, "setSpeedRequest").validate(invalid_body)


def test_session_command_rejects_arbitrary_slot_or_path(protocol_schema: dict) -> None:
    """Save/load contracts must not allow callers to inject filesystem paths."""
    request_body = {
        "commandId": "phase2-load-001",
        "idempotencyKey": "phase2-load-key-001",
        "expectedSessionId": "bridge-offline-fixture",
        "expectedWorldGeneration": "generation:1",
        "expectedStateVersion": 7,
        "timeoutMs": 120000,
        "path": r"C:\Users\Administrator\save",
    }
    with pytest.raises(ValidationError):
        _definition_validator(protocol_schema, "sessionCommandRequest").validate(request_body)


def test_event_sequence_must_be_positive(protocol_schema: dict) -> None:
    """Semantic event sequence numbers start at one and cannot be zero."""
    event = {
        "protocolVersion": "0.1",
        "eventId": "event-001",
        "eventSequence": 0,
        "eventType": "state-version-changed",
        "sessionId": "bridge-offline-fixture",
        "worldGeneration": "generation:2",
        "stateVersion": 8,
        "capturedAt": "2026-09-16T06:00:00Z",
        "previousWorldGeneration": "generation:1",
        "previousStateVersion": 7,
    }
    with pytest.raises(ValidationError):
        _definition_validator(protocol_schema, "event").validate(event)
