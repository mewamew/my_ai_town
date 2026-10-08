"""Read and command concurrency smoke for the isolated GameTestBridge fixture."""

from __future__ import annotations

import json
import time
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any

from locust import HttpUser, between, events, task


PUBLIC_RESIDENT_FIELDS = frozenset(
    "residentId name currentPlace spaceId position doing isPresent".split()
)
BUSINESS_OUTCOMES: Counter[str] = Counter()
BUSINESS_OUTCOMES_LOCK = Lock()


@events.init_command_line_parser.add_listener
def add_evidence_argument(parser) -> None:
    """Add an explicit destination for a final, non-sampled Locust report."""
    parser.add_argument(
        "--evidence-json",
        default="",
        help="Write final Locust request statistics to this JSON file.",
    )
    parser.add_argument(
        "--command-mix",
        action="store_true",
        help="Add set-speed, idempotent replay, receipt, and expected-conflict traffic.",
    )


def _record_outcome(name: str) -> None:
    """Count a verified business outcome separately from HTTP request statistics."""
    with BUSINESS_OUTCOMES_LOCK:
        BUSINESS_OUTCOMES[name] += 1


def _json_safe_exception(value: Any) -> dict[str, Any]:
    """Keep worker exception evidence serializable across Locust versions."""
    if isinstance(value, dict):
        return {
            "count": value.get("count"),
            "message": value.get("msg"),
            "traceback": value.get("traceback"),
            "nodes": sorted(str(node) for node in value.get("nodes", [])),
        }
    return {"message": str(value)}


@events.quitting.add_listener
def write_final_evidence(environment, **_kwargs) -> None:
    """Write exact final counters after users have stopped, avoiding CSV sampling lag."""
    destination = str(getattr(environment.parsed_options, "evidence_json", "")).strip()
    if not destination:
        return

    entries = [entry.to_dict() for entry in environment.stats.entries.values()]
    aggregate = environment.stats.total.to_dict()
    aggregate["name"] = "Aggregated"
    runner_exceptions = getattr(environment.runner, "exceptions", {}) or {}
    payload = {
        "schemaVersion": 1,
        "capturedAt": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
            "+00:00", "Z"
        ),
        "tool": "locust",
        "scenario": "mixed-command" if environment.parsed_options.command_mix else "read",
        "users": getattr(environment.parsed_options, "num_users", None),
        "durationMs": max(0.0, (time.time() - environment.stats.start_time) * 1000.0),
        "stats": [*entries, aggregate],
        "failures": [error.to_dict() for error in environment.stats.errors.values()],
        "exceptions": [
            _json_safe_exception(value) for value in runner_exceptions.values()
        ],
        "businessOutcomes": dict(sorted(BUSINESS_OUTCOMES.items())),
    }
    path = Path(destination).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _json_body(response) -> dict:
    """Return a JSON object or mark the Locust sample as a failed contract."""
    try:
        body = response.json()
    except ValueError as exc:
        response.failure(f"response is not JSON: {exc}")
        return {}
    if not isinstance(body, dict):
        response.failure("response JSON is not an object")
        return {}
    return body


def _error_code(body: dict) -> str:
    """Return a structured Bridge error code while accepting success-side null."""
    error = body.get("error")
    return str(error.get("code") or "") if isinstance(error, dict) else ""


class BridgeReadUser(HttpUser):
    """Exercise public reads and, when requested, command correctness under concurrency."""

    wait_time = between(0.05, 0.2)

    @task(1)
    def health(self) -> None:
        """Verify bridge and world readiness remain visible under concurrency."""
        with self.client.get("/health", name="GET /health", catch_response=True) as response:
            body = _json_body(response)
            data = body.get("data", {})
            if response.status_code != 200:
                response.failure(f"expected 200, got {response.status_code}")
            elif not body.get("ok"):
                response.failure(f"health returned error: {body.get('error')}")
            elif data != {
                "bridgeReady": True,
                "readOnly": not self.environment.parsed_options.command_mix,
                "worldReady": True,
            }:
                response.failure(f"unexpected health payload: {data}")

    @task(3)
    def world_state(self) -> None:
        """Verify count, identity uniqueness, and state metadata."""
        with self.client.get(
            "/world/state", name="GET /world/state", catch_response=True
        ) as response:
            body = _json_body(response)
            data = body.get("data", {})
            residents = data.get("residents", [])
            resident_ids = [resident.get("residentId") for resident in residents]
            if response.status_code != 200:
                response.failure(f"expected 200, got {response.status_code}")
            elif data.get("residentCount") != 15 or len(residents) != 15:
                response.failure(f"unexpected resident count: {data.get('residentCount')}")
            elif len(set(resident_ids)) != len(resident_ids):
                response.failure("resident IDs are not unique")
            elif not data.get("worldGeneration") or not isinstance(
                data.get("stateVersion"), int
            ):
                response.failure("world metadata is incomplete")

    @task(1)
    def resident_detail(self) -> None:
        """Verify a stable fixture resident still exposes only public fields."""
        with self.client.get(
            "/residents/resident_a_he_01",
            name="GET /residents/:id",
            catch_response=True,
        ) as response:
            body = _json_body(response)
            resident = body.get("data", {}).get("resident", {})
            if response.status_code != 200:
                response.failure(f"expected 200, got {response.status_code}")
            elif set(resident) != PUBLIC_RESIDENT_FIELDS:
                response.failure(f"unexpected resident fields: {sorted(resident)}")

    @task(2)
    def command_roundtrip(self) -> None:
        """Verify write, replay, receipt, and expected conflict as one business flow."""
        if not self.environment.parsed_options.command_mix:
            self.world_state()
            return

        snapshot = self._command_snapshot()
        if not snapshot:
            return
        identifier = f"locust-{uuid.uuid4().hex}"
        target_speed = 2 if snapshot["simulationSpeed"] != 2 else 3
        preconditions = {
            target: snapshot[source]
            for target, source in {
                "expectedSessionId": "sessionId",
                "expectedWorldGeneration": "worldGeneration",
                "expectedStateVersion": "stateVersion",
            }.items()
        }
        command = {
            "commandId": identifier,
            "idempotencyKey": identifier,
            **preconditions,
            "timeoutMs": 3000,
            "speed": target_speed,
        }
        receipt = self._submit_initial_command(command)
        if not receipt:
            return
        self._verify_replay(command, receipt)
        self._verify_receipt(identifier, receipt)
        self._verify_expected_conflict(command, target_speed)

    def _command_snapshot(self) -> dict:
        """Read a versioned command precondition without hiding contract failures."""
        with self.client.get(
            "/world/state",
            name="GET /world/state [command setup]",
            catch_response=True,
        ) as response:
            body = _json_body(response)
            data = body.get("data", {})
            required = {
                "sessionId",
                "worldGeneration",
                "stateVersion",
                "simulationSpeed",
            }
            if response.status_code != 200 or not body.get("ok"):
                response.failure(f"command setup failed: HTTP {response.status_code}")
                return {}
            if not required.issubset(data):
                response.failure(f"command setup metadata is incomplete: {data}")
                return {}
            return data

    def _submit_initial_command(self, command: dict) -> dict:
        """Accept either one valid mutation or an explicit concurrent-version race."""
        with self.client.post(
            "/commands/set-speed",
            name="POST /commands/set-speed [initial]",
            json=command,
            catch_response=True,
        ) as response:
            body = _json_body(response)
            error_code = _error_code(body)
            if response.status_code == 409 and error_code == "STATE_VERSION_CONFLICT":
                response.success()
                _record_outcome("expected_state_version_conflict")
                return {}
            data = body.get("data", {})
            if response.status_code != 200 or not body.get("ok"):
                response.failure(
                    f"initial command failed: HTTP {response.status_code} {error_code}"
                )
                return {}
            if (
                data.get("commandId") != command["commandId"]
                or data.get("status") != "completed"
                or data.get("result", {}).get("simulationSpeed") != command["speed"]
            ):
                response.failure(f"invalid command receipt: {data}")
                return {}
            _record_outcome("command_completed")
            return data

    def _verify_replay(self, command: dict, receipt: dict) -> None:
        """A byte-equivalent retry must return the original receipt."""
        with self.client.post(
            "/commands/set-speed",
            name="POST /commands/set-speed [idempotent replay]",
            json=command,
            catch_response=True,
        ) as response:
            body = _json_body(response)
            if response.status_code != 200 or body.get("data") != receipt:
                response.failure(f"idempotent replay changed receipt: {body}")
                return
            _record_outcome("idempotent_replay_verified")

    def _verify_receipt(self, command_id: str, receipt: dict) -> None:
        """The query endpoint must expose the same terminal command result."""
        with self.client.get(
            f"/commands/{command_id}",
            name="GET /commands/:id [terminal receipt]",
            catch_response=True,
        ) as response:
            body = _json_body(response)
            if response.status_code != 200 or body.get("data") != receipt:
                response.failure(f"queried receipt differs: {body}")
                return
            _record_outcome("terminal_receipt_verified")

    def _verify_expected_conflict(self, command: dict, target_speed: int) -> None:
        """Changed work under one idempotency key is a correct 409, not a load failure."""
        changed = {
            **command,
            "speed": 1 if target_speed != 1 else 3,
        }
        with self.client.post(
            "/commands/set-speed",
            name="POST /commands/set-speed [expected idempotency conflict]",
            json=changed,
            catch_response=True,
        ) as response:
            body = _json_body(response)
            error_code = _error_code(body)
            if response.status_code != 409 or error_code != "IDEMPOTENCY_CONFLICT":
                response.failure(
                    f"expected 409 IDEMPOTENCY_CONFLICT, got "
                    f"{response.status_code} {error_code}"
                )
                return
            response.success()
            _record_outcome("expected_idempotency_conflict")
