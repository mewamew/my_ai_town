"""Append-only JSONL and SQLite evidence for Phase 2 test runs."""

from __future__ import annotations

import json
import base64
import hashlib
import queue
import platform
import secrets
import socket
import sqlite3
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


SCHEMA_VERSION = 1


def _utc_now() -> str:
    """Return an ISO-8601 UTC timestamp with an explicit Z suffix."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _json(value: Any) -> str:
    """Serialize structured columns deterministically for later comparison."""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def new_run_id(tool: str) -> str:
    """Create a readable globally unique run identifier."""
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return f"{tool}-{timestamp}-{uuid.uuid4().hex[:8]}"


class BridgeEventStream:  # pylint: disable=too-many-instance-attributes
    """Collect the Bridge's bounded, unfragmented server frames without third-party tools.

    The reader thread never writes SQLite. The pytest thread drains received data,
    preserving source event IDs separately from EvidenceStore's generated IDs.
    Unsupported frames, disconnects and overflow are explicit tracing gaps.
    """

    def __init__(self, base_url: str) -> None:
        self.base_url = base_url
        self.connection_id = f"test-connection-{uuid.uuid4().hex}"
        self.endpoints: dict[str, Any] = {}
        self._socket: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._buffer = bytearray()
        self._received: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=2048)
        self._overflow = False
        self._receive_index = 0

    def start(self) -> None:
        """Finish the upgrade before callers issue any command; retain upgrade leftovers."""
        location = urlsplit(self.base_url)
        if location.scheme != "http" or location.hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("event tracing requires an explicit loopback HTTP Bridge")
        port = location.port or 80
        self._socket = socket.create_connection((location.hostname, port), timeout=3.0)
        try:
            self.endpoints = {"local": self._socket.getsockname(),
                              "peer": self._socket.getpeername()}
            deadline = time.monotonic() + 3.0
            key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
            self._socket.sendall((
                f"GET /events HTTP/1.1\r\nHost: {location.hostname}:{port}\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                f"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n"
            ).encode("ascii"))
            while b"\r\n\r\n" not in self._buffer:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("event upgrade exceeded 3s deadline")
                self._socket.settimeout(remaining)
                incoming = self._socket.recv(4096)
                if not incoming:
                    raise ConnectionError("event upgrade closed before headers completed")
                self._buffer.extend(incoming)
                if len(self._buffer) > 8192:
                    raise ValueError("event upgrade header exceeds the tracing limit")
            header, leftover = bytes(self._buffer).split(b"\r\n\r\n", 1)
            lines = header.decode("ascii").split("\r\n")
            headers = {name.lower(): value.strip() for name, value in
                       (line.split(":", 1) for line in lines[1:] if ":" in line)}
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii"),
                usedforsecurity=False,
            ).digest()).decode("ascii")
            if (not lines[0].startswith("HTTP/1.1 101 ")
                    or headers.get("sec-websocket-accept", "") != expected
                    or headers.get("upgrade", "").lower() != "websocket"
                    or "upgrade" not in headers.get("connection", "").lower()):
                raise ValueError("event upgrade did not return a valid 101/accept pair")
            self._buffer = bytearray(leftover)
            self._socket.settimeout(0.2)
            self._thread = threading.Thread(target=self._read_loop, daemon=True)
            self._thread.start()
        except (OSError, ValueError):
            self.close()
            raise

    def _read_exact(self, size: int) -> bytes:
        while len(self._buffer) < size:
            if self._stop.is_set():
                raise ConnectionError("event reader stopped")
            try:
                incoming = self._socket.recv(4096)
            except socket.timeout:
                continue
            if not incoming:
                raise ConnectionError("event peer disconnected")
            self._buffer.extend(incoming)
        result = bytes(self._buffer[:size])
        del self._buffer[:size]
        return result

    def _read_loop(self) -> None:
        try:
            while not self._stop.is_set():
                first, second = self._read_exact(2)
                if first != 0x81 or second & 0x80:
                    raise ValueError("unsupported event frame: expected unmasked FIN text")
                length = second & 0x7f
                if length == 126:
                    length = int.from_bytes(self._read_exact(2), "big")
                elif length == 127:
                    length = int.from_bytes(self._read_exact(8), "big")
                if length > 65536:
                    raise ValueError("event frame exceeds the 64 KiB tracing limit")
                raw = self._read_exact(length)
                value = json.loads(raw.decode("utf-8"))
                if not isinstance(value, dict):
                    raise ValueError("event payload is not a JSON object")
                self._receive_index += 1
                self._received.put_nowait({
                    "gameEvent": value, "receivedAt": _utc_now(),
                    "receiveIndex": self._receive_index,
                    "wirePayloadSha256": hashlib.sha256(raw).hexdigest(),
                    "connectionId": self.connection_id,
                })
        except queue.Full:
            self._overflow = True
        except (OSError, ValueError) as error:
            if not self._stop.is_set():
                try:
                    self._received.put_nowait({
                        "traceError": type(error).__name__, "message": str(error),
                        "receivedAt": _utc_now(),
                        "connectionId": self.connection_id,
                    })
                except queue.Full:
                    self._overflow = True

    def drain(self) -> list[dict[str, Any]]:
        """Return every received observation, including an explicit overflow marker."""
        result = []
        while True:
            try:
                result.append(self._received.get_nowait())
            except queue.Empty:
                break
        if self._overflow:
            result.append({"traceError": "BufferOverflow", "receivedAt": _utc_now(),
                           "connectionId": self.connection_id})
            self._overflow = False
        return result

    def request_policy_disconnect(self) -> dict[str, Any]:
        """Send a real masked text frame, rejected by the existing receive-only policy."""
        if self._socket is None or self._stop.is_set():
            raise ValueError("policy injection requires a live subscription")
        payload = b"disconnect-policy-probe"
        mask = secrets.token_bytes(4)
        frame = bytes([0x81, 0x80 | len(payload)]) + mask + bytes(
            value ^ mask[index % 4] for index, value in enumerate(payload))
        self._socket.sendall(frame)
        return {"opcode": "text", "masked": True, "payloadBytes": len(payload),
                "payloadSha256": hashlib.sha256(payload).hexdigest()}

    def resource_state(self) -> dict[str, Any]:
        """Observe only this test reader and socket, not server-side memory ownership."""
        return {"connectionId": self.connection_id, "endpoints": self.endpoints,
                "readerAlive": self._thread is not None and self._thread.is_alive(),
                "socketClosed": self._socket is None or self._socket.fileno() == -1}

    def close(self) -> None:
        """Stop this reader only, without deleting or modifying any artifact."""
        self._stop.set()
        if self._socket is not None:
            try:
                self._socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._socket.close()
        if self._thread is not None:
            self._thread.join(timeout=1.0)


class EvidenceStore:  # pylint: disable=too-many-instance-attributes
    """Write every evidence event to JSONL and SQLite from one payload."""

    def __init__(
        self,
        root: Path,
        tool: str,
        *,
        run_id: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.tool = tool
        self.run_id = run_id or new_run_id(tool)
        self.jsonl_path = self.root / f"{self.run_id}.jsonl"
        self.sqlite_path = self.root / "phase2_evidence.sqlite3"
        self.started_at = _utc_now()
        self._sequence = 0
        self._finished = False
        self._connection = sqlite3.connect(self.sqlite_path)
        self._connection.execute("PRAGMA foreign_keys = ON")
        self._create_schema()

        run_metadata = {
            "python": sys.version.split()[0],
            "platform": platform.platform(),
            **(metadata or {}),
        }
        self._connection.execute(
            """
            INSERT INTO runs (
                run_id, schema_version, tool, started_at, status, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                self.run_id,
                SCHEMA_VERSION,
                self.tool,
                self.started_at,
                "running",
                _json(run_metadata),
            ),
        )
        self._connection.commit()
        self.record("run_started", name=self.tool, status="running", details=run_metadata)

    def _create_schema(self) -> None:
        self._connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS runs (
                run_id TEXT PRIMARY KEY,
                schema_version INTEGER NOT NULL,
                tool TEXT NOT NULL,
                started_at TEXT NOT NULL,
                finished_at TEXT,
                status TEXT NOT NULL,
                total INTEGER,
                passed INTEGER,
                failed INTEGER,
                skipped INTEGER,
                other INTEGER,
                duration_ms REAL,
                metadata_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS evidence_events (
                event_id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                recorded_at TEXT NOT NULL,
                event_type TEXT NOT NULL,
                name TEXT,
                status TEXT,
                duration_ms REAL,
                error_type TEXT,
                message TEXT,
                request_id TEXT,
                command_id TEXT,
                session_id TEXT,
                world_generation TEXT,
                state_version INTEGER,
                event_sequence INTEGER,
                details_json TEXT NOT NULL,
                FOREIGN KEY (run_id) REFERENCES runs(run_id),
                UNIQUE (run_id, sequence)
            );

            CREATE INDEX IF NOT EXISTS evidence_events_run_type_idx
            ON evidence_events (run_id, event_type, status);
            """
        )
        self._connection.commit()

    def record(  # pylint: disable=too-many-locals
        self,
        event_type: str,
        *,
        name: str | None = None,
        status: str | None = None,
        duration_ms: float | None = None,
        error_type: str | None = None,
        message: str | None = None,
        request_id: str | None = None,
        command_id: str | None = None,
        session_id: str | None = None,
        world_generation: str | None = None,
        state_version: int | None = None,
        event_sequence: int | None = None,
        details: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Append one normalized event and return the exact JSONL payload."""
        if self._finished:
            raise RuntimeError("cannot append evidence after the run has finished")

        self._sequence += 1
        evidence_id = str(uuid.uuid4())
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "eventId": evidence_id,
            "testEvidenceId": evidence_id,
            "runId": self.run_id,
            "sequence": self._sequence,
            "recordedAt": _utc_now(),
            "tool": self.tool,
            "eventType": event_type,
            "name": name,
            "status": status,
            "durationMs": duration_ms,
            "errorType": error_type,
            "message": message,
            "requestId": request_id,
            "commandId": command_id,
            "sessionId": session_id,
            "worldGeneration": world_generation,
            "stateVersion": state_version,
            "eventSequence": event_sequence,
            "details": details or {},
        }
        with self.jsonl_path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(_json(payload) + "\n")

        self._connection.execute(
            """
            INSERT INTO evidence_events (
                event_id, run_id, sequence, recorded_at, event_type, name, status,
                duration_ms, error_type, message, request_id, command_id,
                session_id, world_generation, state_version, event_sequence,
                details_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload["eventId"],
                payload["runId"],
                payload["sequence"],
                payload["recordedAt"],
                payload["eventType"],
                payload["name"],
                payload["status"],
                payload["durationMs"],
                payload["errorType"],
                payload["message"],
                payload["requestId"],
                payload["commandId"],
                payload["sessionId"],
                payload["worldGeneration"],
                payload["stateVersion"],
                payload["eventSequence"],
                _json(payload["details"]),
            ),
        )
        self._connection.commit()
        return payload

    def finish(
        self,
        *,
        status: str,
        total: int,
        passed: int,
        failed: int,
        skipped: int,
        other: int,
        duration_ms: float,
    ) -> None:
        """Write the terminal event and finalize the matching run row."""
        summary = {
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "other": other,
        }
        self.record(
            "run_finished",
            name=self.tool,
            status=status,
            duration_ms=duration_ms,
            details=summary,
        )
        finished_at = _utc_now()
        self._connection.execute(
            """
            UPDATE runs
            SET finished_at = ?, status = ?, total = ?, passed = ?, failed = ?,
                skipped = ?, other = ?, duration_ms = ?
            WHERE run_id = ?
            """,
            (
                finished_at,
                status,
                total,
                passed,
                failed,
                skipped,
                other,
                duration_ms,
                self.run_id,
            ),
        )
        self._connection.commit()
        self._finished = True
        self._connection.close()
