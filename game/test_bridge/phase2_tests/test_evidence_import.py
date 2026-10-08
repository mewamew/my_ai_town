"""Tests for importing external tool reports into shared evidence."""

from __future__ import annotations

import csv
import ctypes
import hashlib
import json
import sqlite3
import shutil
import subprocess
import sys
import time
from os import environ  # pylint: disable=no-name-in-module
from pathlib import Path

import pytest

from game.test_bridge.evidence_import import (  # pylint: disable=import-error
    import_ci_summary,
    import_jenkins_summary,
    import_locust_final_json,
    import_locust_report,
    import_newman_report,
)
from game.test_bridge.evidence_store import EvidenceStore  # pylint: disable=import-error


def _latest_run(root: Path, run_id: str) -> tuple:
    with sqlite3.connect(root / "phase2_evidence.sqlite3") as connection:
        return connection.execute(
            """
            SELECT tool, status, total, passed, failed, skipped, other
            FROM runs WHERE run_id = ?
            """,
            (run_id,),
        ).fetchone()


def test_newman_assertions_and_correlations_are_imported(tmp_path: Path) -> None:
    """Newman assertions and Bridge IDs remain traceable in both formats."""
    response = {
        "requestId": "request-7",
        "data": {
            "sessionId": "session-7",
            "worldGeneration": "world-7",
            "stateVersion": 7,
        },
    }
    report = {
        "run": {
            "timings": {"started": 1000, "completed": 1042},
            "executions": [
                {
                    "item": {"name": "World state"},
                    "response": {
                        "code": 200,
                        "responseTime": 8,
                        "stream": {
                            "type": "Buffer",
                            "data": list(json.dumps(response).encode("utf-8")),
                        },
                    },
                    "assertions": [
                        {"assertion": "HTTP 200"},
                        {"assertion": "15 residents"},
                    ],
                }
            ],
        }
    }
    report_path = tmp_path / "newman.json"
    report_path.write_text(json.dumps(report), encoding="utf-8")

    run_id = import_newman_report(report_path, tmp_path)

    assert _latest_run(tmp_path, run_id) == ("newman", "passed", 2, 2, 0, 0, 0)
    events = [
        json.loads(line)
        for line in (tmp_path / f"{run_id}.jsonl").read_text(encoding="utf-8").splitlines()
    ]
    assertion = next(event for event in events if event["eventType"] == "assertion")
    assert assertion["requestId"] == "request-7"
    assert assertion["sessionId"] == "session-7"
    assert assertion["worldGeneration"] == "world-7"
    assert assertion["stateVersion"] == 7


def test_locust_aggregate_and_failures_are_imported(tmp_path: Path) -> None:
    """Locust counts, percentiles, and errors remain queryable."""
    fieldnames = [
        "Type",
        "Name",
        "Request Count",
        "Failure Count",
        "Average Response Time",
        "Max Response Time",
        "Requests/s",
        "50%",
        "95%",
        "99%",
    ]
    stats_path = tmp_path / "locust_stats.csv"
    with stats_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow(
            {
                "Type": "GET",
                "Name": "GET /health",
                "Request Count": "9",
                "Failure Count": "1",
                "Average Response Time": "6",
                "Max Response Time": "20",
                "Requests/s": "3.5",
                "50%": "5",
                "95%": "9",
                "99%": "12",
            }
        )
        writer.writerow(
            {
                "Type": "",
                "Name": "Aggregated",
                "Request Count": "9",
                "Failure Count": "1",
                "Average Response Time": "6",
                "Max Response Time": "20",
                "Requests/s": "3.5",
                "50%": "5",
                "95%": "9",
                "99%": "12",
            }
        )
    failures_path = tmp_path / "locust_failures.csv"
    with failures_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["Method", "Name", "Error", "Occurrences"])
        writer.writeheader()
        writer.writerow(
            {
                "Method": "GET",
                "Name": "GET /health",
                "Error": "expected 200",
                "Occurrences": "1",
            }
        )

    run_id = import_locust_report(stats_path, failures_path, evidence_root=tmp_path)

    assert _latest_run(tmp_path, run_id) == ("locust", "failed", 9, 8, 1, 0, 0)
    with sqlite3.connect(tmp_path / "phase2_evidence.sqlite3") as connection:
        p95 = connection.execute(
            """
            SELECT json_extract(details_json, '$.p95Ms')
            FROM evidence_events
            WHERE run_id = ? AND event_type = 'load_metric' AND name = 'Aggregated'
            """,
            (run_id,),
        ).fetchone()[0]
        error_count = connection.execute(
            """
            SELECT count(*) FROM evidence_events
            WHERE run_id = ? AND event_type = 'load_error'
            """,
            (run_id,),
        ).fetchone()[0]
    assert p95 == 9.0
    assert error_count == 1


def test_locust_final_snapshot_is_preferred_over_sampled_csv(tmp_path: Path) -> None:
    """The quitting-event snapshot must preserve the exact terminal counters."""
    report = {
        "users": 5,
        "scenario": "mixed-command",
        "durationMs": 10000.0,
        "stats": [
            {
                "method": None,
                "name": "Aggregated",
                "num_requests": 341,
                "num_failures": 0,
                "avg_response_time": 6.0,
                "total_rps": 35.98,
                "response_time_percentile_0.5": 6,
                "response_time_percentile_0.95": 10,
                "response_time_percentile_0.99": 10,
                "max_response_time": 19,
            }
        ],
        "failures": [],
        "exceptions": [],
        "businessOutcomes": {
            "command_completed": 18,
            "expected_state_version_conflict": 3,
            "idempotent_replay_verified": 18,
        },
    }
    report_path = tmp_path / "locust-final.json"
    report_path.write_text(json.dumps(report), encoding="utf-8")

    run_id = import_locust_final_json(report_path, tmp_path)

    assert _latest_run(tmp_path, run_id) == ("locust", "passed", 341, 341, 0, 0, 0)
    with sqlite3.connect(tmp_path / "phase2_evidence.sqlite3") as connection:
        metadata = connection.execute(
            """
            SELECT json_extract(metadata_json, '$.users'),
                   json_extract(metadata_json, '$.scenario')
            FROM runs WHERE run_id = ?
            """,
            (run_id,),
        ).fetchone()
        outcomes = dict(
            connection.execute(
                """
                SELECT name, json_extract(details_json, '$.count')
                FROM evidence_events
                WHERE run_id = ? AND event_type = 'business_outcome'
                """,
                (run_id,),
            ).fetchall()
        )
    assert metadata == (5, "mixed-command")
    assert outcomes == report["businessOutcomes"]


def test_jenkins_stages_and_source_fingerprint_are_imported(tmp_path: Path) -> None:
    """CI stage outcomes remain tied to the exact tested source fingerprint."""

    report = {
        "runId": "jenkins-build-7",
        "buildNumber": "7",
        "executionMode": "jenkins",
        "status": "failed",
        "durationMs": 1250.5,
        "sourceFingerprint": {
            "head": "abc123",
            "trackedDiffSha256": "tracked-hash",
            "untrackedSha256": "untracked-hash",
        },
        "toolVersions": {"python": "3.11.16", "jenkins": "2.568.3"},
        "disk": {"artifactsBytes": 1024},
        "stages": [
            {
                "name": "preflight",
                "status": "passed",
                "durationMs": 250.0,
                "exitCode": 0,
                "reportPaths": [],
            },
            {
                "name": "pytest",
                "status": "failed",
                "durationMs": 1000.5,
                "exitCode": 1,
                "errorType": "StageFailure",
                "message": "pytest exited with code 1",
                "reportPaths": ["pytest-junit.xml"],
            },
        ],
    }
    report_path = tmp_path / "jenkins-summary.json"
    report_path.write_text(json.dumps(report), encoding="utf-8")

    run_id = import_jenkins_summary(report_path, tmp_path)

    assert _latest_run(tmp_path, run_id) == ("jenkins", "failed", 2, 1, 1, 0, 0)
    with sqlite3.connect(tmp_path / "phase2_evidence.sqlite3") as connection:
        fingerprint = connection.execute(
            """
            SELECT json_extract(metadata_json, '$.sourceFingerprint.trackedDiffSha256')
            FROM runs WHERE run_id = ?
            """,
            (run_id,),
        ).fetchone()[0]
        failed_stage = connection.execute(
            """
            SELECT name, json_extract(details_json, '$.exitCode')
            FROM evidence_events
            WHERE run_id = ? AND event_type = 'ci_stage' AND status = 'failed'
            """,
            (run_id,),
        ).fetchone()
    assert fingerprint == "tracked-hash"
    assert failed_stage == ("pytest", 1)

    report["runId"] = "actions-run-8"
    report["executionMode"] = "github-actions"
    report_path.write_text(json.dumps(report), encoding="utf-8")
    actions_run_id = import_ci_summary(report_path, tmp_path)
    assert _latest_run(tmp_path, actions_run_id) == ("ci", "failed", 2, 1, 1, 0, 0)


def test_ci_native_stderr_and_exit_code_preserve_utf8_evidence(
    tmp_path: Path, pytestconfig: pytest.Config,
) -> None:
    """Real shell/child probes test the runner, not mocked game or save evidence."""
    shell = shutil.which("powershell.exe") or shutil.which("pwsh")
    assert shell, "The Windows CI runner requires PowerShell"
    runner = Path(pytestconfig.rootpath) / "run_phase2_ci.ps1"
    positive = tmp_path / "native-success.log"
    negative = tmp_path / "native-failure.log"
    script = tmp_path / "native-log-boundary.ps1"
    script.write_text(
        'Set-StrictMode -Version Latest\n$ErrorActionPreference="Stop"\n'
        '$probeTokens=$null; $probeErrors=$null\n'
        '$probeAst=[System.Management.Automation.Language.Parser]::ParseFile('
        f'{json.dumps(runner.as_posix())},[ref]$probeTokens,[ref]$probeErrors)\n'
        'if ($probeErrors) { throw "Runner parse errors" }\n'
        '$probeFunction=$probeAst.Find({param($node) '
        '$node -is [System.Management.Automation.Language.FunctionDefinitionAst] '
        '-and $node.Name -eq "Invoke-LoggedCommand"},$true)\n'
        'Invoke-Expression $probeFunction.Extent.Text\n'
        f'Invoke-LoggedCommand -FilePath {json.dumps(Path(sys.executable).as_posix())} '
        '-Arguments @("-c","import sys; print(123); sys.stderr.write(str(456))") '
        f'-LogPath {json.dumps(positive.as_posix())}\n'
        'try {\n'
        f'Invoke-LoggedCommand -FilePath {json.dumps(Path(sys.executable).as_posix())} '
        '-Arguments @("-c","import sys; sys.stderr.write(str(789)); sys.exit(3)") '
        f'-LogPath {json.dumps(negative.as_posix())}\n'
        'throw "Nonzero exit incorrectly accepted"\n'
        '} catch { if ($_.Exception.Message -notlike "*exit code 3*") { throw } }\n'
        'Write-Output "NATIVE_LOG_BOUNDARY_PASS"\n', encoding="utf-8-sig",
    )
    completed = subprocess.run(
        [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=15, check=False,
    )
    (tmp_path / "shell-output.log").write_text(completed.stdout + completed.stderr,
                                               encoding="utf-8")
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "NATIVE_LOG_BOUNDARY_PASS" in completed.stdout
    for log_path, markers in ((positive, ("123", "456")), (negative, ("789",))):
        content = log_path.read_text("utf-8-sig")
        assert "\x00" not in content, "Mixed UTF-16/UTF-8 evidence is not acceptable"
        assert all(marker in content for marker in markers)


_RETENTION_DRIVER = r'''extends SceneTree
const FS = preload("res://agent/AgentFileSystem.gd")
const AGENT = preload("res://agent/AgentSystem.gd")
const AGENT_STORE = preload("res://agent/lifecycle/AgentSaveStore.gd")
const STORE = preload("res://world/presentation/session/TownSessionSaveStore.gd")
const JSON_NUMBERS = preload("res://agent/AgentJson.gd")
const MODEL = preload("res://tests/agent/support/ScriptedModelProvider.gd")
const WORLD = preload("res://world/runtime/TownWorldRuntime.gd")
const BUILDER = preload("res://world/data/town/TownWorldDataBuilder.gd")
const GATE = preload("res://world/presentation/session/TownSessionRuntimeGate.gd")
const COORDINATOR = preload("res://world/presentation/session/TownSessionSaveCoordinator.gd")
const MEMORY = preload("res://agent/memory/ResidentMemorySystem.gd")
const MEMORY_STORE = preload("res://agent/memory/ResidentMemoryStore.gd")
const ENTRY_STORE = preload("res://agent/memory/ResidentMemoryEntryStore.gd")
const INTERVENTION_STORE = preload("res://agent/memory/ResidentMemoryInterventionStore.gd")
const QUEUE = preload("res://agent/memory/ResidentEvidenceQueue.gd")
const AVATAR_STORE = preload("res://agent/avatar_memory/ResidentAvatarMemoryStore.gd")
const AVATAR_QUEUE = preload("res://agent/avatar_memory/ResidentAvatarEvidenceQueue.gd")
var spec: Dictionary
var checks: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(id: String, condition: bool, actual: Variant = null) -> void:
	checks.append({"id": id, "passed": condition, "actual": actual})
	print("RETENTION_CHECK " + JSON.stringify(checks.back()))

func read_json(path: String) -> Dictionary:
	return JSON_NUMBERS.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(path))) as Dictionary

func _run() -> void:
	spec = read_json(OS.get_cmdline_user_args()[0])
	var sandbox := String(spec["sandbox"])
	var configured := FS.configure_test_retention(sandbox)
	check("explicit-enrollment", configured == OK, int(configured))
	if configured != OK:
		quit(1)
		return
	if spec["mode"] == "filesystem":
		filesystem(sandbox)
	elif spec["mode"] == "agent":
		agent_lifecycle(sandbox)
	elif spec["mode"] == "lease":
		lease_lifecycle(sandbox)
	elif spec["mode"] == "memory":
		memory_cleanup(sandbox)
	else:
		coordinator_restore(sandbox)
	for _index in 5:
		await process_frame
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	print("RETENTION_RESULTS " + JSON.stringify(checks))
	quit(0 if checks.all(func(item): return item["passed"]) else 1)

func filesystem(sandbox: String) -> void:
	var owned := sandbox.path_join("owned")
	var source := owned.path_join("tree")
	check("real-directory-move", FS.remove_tree(source) == OK)
	check("source-namespace-released", not DirAccess.dir_exists_absolute(source))
	check("retained-content", FileAccess.get_file_as_string(
		sandbox.path_join("retained/00000001/sub/data.bin")) == "retained-payload")
	check("target-collision-rejected", FS.remove_tree(owned.path_join("collision")) == ERR_ALREADY_EXISTS)
	check("collision-source-preserved", FileAccess.file_exists(owned.path_join("collision/data.bin")))
	for candidate: String in [owned, sandbox, String(spec["foreign"]),
		owned + "/tree/../escape", "user://agent_runtime_memory/nonexistent"]:
		check("path-denied-" + candidate, FS.remove_tree(candidate) == ERR_INVALID_PARAMETER)
	check("junction-rejected", FS.remove_tree(owned.path_join("junction")) == ERR_INVALID_PARAMETER)
	check("nested-junction-rejected", FS.remove_tree(owned.path_join("linked-tree")) == ERR_INVALID_PARAMETER)
	check("native-move-failure-propagated", FS.remove_tree(owned.path_join("locked")) != OK)
	check("native-move-failure-source-preserved", FileAccess.file_exists(owned.path_join("locked/data.bin")))
	check("existing-file-move", FS.retain_for_test(owned.path_join("single.bin")) == OK)
	FS.remove_empty_directory(owned.path_join("empty"))
	check("empty-test-parent-kept", DirAccess.dir_exists_absolute(owned.path_join("empty")))
	check("second-enrollment-denied", FS.configure_test_retention(sandbox) == ERR_ALREADY_IN_USE)

func lease_lifecycle(sandbox: String) -> void:
	var store: RefCounted = STORE.new()
	store.set("_root", sandbox.path_join("owned/town_session_saves"))
	var lease: Dictionary = store.call("begin_slot_transaction", "roundtrip-slot-beta6")
	check("real-lease-acquired", lease.get("ok") == true, lease)
	if lease.get("ok") != true:
		return
	check("real-lease-release-retained", store.call("end_slot_transaction", lease["leaseToken"]).get("ok") == true)
	check("lease-ownership-released", (store.get("_owned_slot_transactions") as Dictionary).is_empty())
	var second: Dictionary = store.call("begin_slot_transaction", "roundtrip-slot-beta6")
	check("real-lease-reacquired", second.get("ok") == true)
	if second.get("ok") == true:
		check("reacquired-lease-released", store.call("end_slot_transaction", second["leaseToken"]).get("ok") == true)
	var third: Dictionary = store.call("begin_slot_transaction", "roundtrip-slot-beta6")
	check("lease-for-failure-acquired", third.get("ok") == true)
	if third.get("ok") == true:
		DirAccess.make_dir_absolute(sandbox.path_join("retained/00000003"))
		var failed: Dictionary = store.call("end_slot_transaction", third["leaseToken"])
		check("lease-retention-conflict-reported", failed.get("ok") == false and failed.get("errorCode") == "SESSION_SAVE_STORE_CLEANUP_FAILED", failed)
		check("failed-release-keeps-ownership", (store.get("_owned_slot_transactions") as Dictionary).has(third["leaseToken"]))
		check("failed-release-retry-succeeds", store.call("end_slot_transaction", third["leaseToken"]).get("ok") == true)
	check("store-native-file-failure-reported", store.call("_remove_entry", sandbox.path_join("owned/locked")) != OK)

func new_agent(sandbox: String, suffix: String) -> RefCounted:
	var store: RefCounted = AGENT_STORE.new()
	store.set("_store_root", sandbox.path_join("owned/agent_saves"))
	var system: RefCounted = AGENT.new(store)
	var base := sandbox.path_join("owned/runtime-" + suffix)
	DirAccess.make_dir_absolute(base)
	system.set("_runtime_memory_root_base", base)
	system.set("_memory_root", base.path_join("initial"))
	return system

func agent_lifecycle(sandbox: String) -> void:
	var context: Dictionary = spec["context"]
	var system := new_agent(sandbox, "lifecycle")
	var prepared: Dictionary = system.call("restore_game", context)
	check("real-agent-prepare-15", prepared.get("ok") == true and prepared.get("resident_ids", []).size() == 15, prepared)
	if prepared.get("ok") != true:
		return
	check("cancel-unhydrated-15", system.call("cancel_restore").get("ok") == true)
	# Empty real sessions exercise commit/cancel/close without entering the
	# separately blocked resident-memory file deletion paths.
	var empty_context := {"slot_id": "retention-empty", "session_id": "retention-empty", "save_revision": 0}
	check("real-empty-session-prepared", system.call("start_new_game", empty_context).get("ok") == true)
	check("real-empty-session-committed", system.call("finish_new_game").get("ok") == true)
	var before: Dictionary = system.call("get_save_context")
	var active_root := String(system.get("_memory_root"))
	DirAccess.make_dir_absolute(active_root)
	var evidence_file := FileAccess.open(active_root.path_join("sentinel.bin"), FileAccess.WRITE)
	evidence_file.store_string("active-session-evidence")
	evidence_file = null
	check("prepare-second-restore", system.call("restore_game", context).get("ok") == true)
	var cancelled: Dictionary = system.call("cancel_restore")
	check("real-cancel", cancelled.get("ok") == true, cancelled)
	check("cancel-preserves-old-session", system.call("get_save_context") == before and system.get("_memory_root") == active_root)
	check("prepare-incomplete-restore", system.call("restore_game", context).get("ok") == true)
	var incomplete: Dictionary = system.call("finish_restore")
	check("missing-hydration-rejected", incomplete.get("ok") == false, incomplete)
	check("abort-preserves-old-session", system.call("get_save_context") == before and system.get("_memory_root") == active_root)
	check("abort-clears-pending-transaction", (system.get("_pending_restore") as Dictionary).is_empty())
	# This path is a real OS lock, held by Python without FILE_SHARE_DELETE.
	var blocked_root := sandbox.path_join("owned/locked")
	system.set("_runtime_memory_root_base", sandbox.path_join("owned"))
	check("prepare-retention-failure", system.call("restore_game", context).get("ok") == true)
	var pending: Dictionary = system.get("_pending_restore")
	var pending_root := String(pending["memory_root"])
	pending["memory_root"] = blocked_root
	var failed_cancel: Dictionary = system.call("cancel_restore")
	check("cancel-reports-native-failure", failed_cancel.get("ok") == false and failed_cancel.get("errorCode") == "AGENT_TEST_RETENTION_FAILED", failed_cancel)
	check("failed-cancel-keeps-transaction", not (system.get("_pending_restore") as Dictionary).is_empty() and system.call("get_save_context") == before)
	pending["memory_root"] = pending_root
	check("cancel-retry-keeps-active-context", system.call("cancel_restore").get("ok") == true and system.call("get_save_context") == before)
	system.set("_memory_root", blocked_root)
	var closed: Dictionary = system.call("close_game")
	check("close-reports-native-move-failure", closed.get("ok") == false and closed.get("errorCode") == "AGENT_TEST_RETENTION_FAILED", closed)
	check("failed-close-keeps-context-and-root", system.call("get_save_context") == before and system.get("_memory_root") == blocked_root)
	system.set("_memory_root", active_root)
	check("real-empty-restore-commit", system.call("restore_game", empty_context).get("ok") == true)
	check("empty-restore-context-preserved", system.call("get_save_context") == empty_context)
	check("real-close-retains-runtime", system.call("close_game").get("ok") == true)
	check("close-releases-session", (system.call("get_save_context") as Dictionary).is_empty())

func memory_cleanup(sandbox: String) -> void:
	var path := sandbox.path_join("owned/locked/data.bin")
	var stores: Array[RefCounted] = [MEMORY_STORE.new(path), ENTRY_STORE.new(path, "resident-test"),
		INTERVENTION_STORE.new(path, "resident-test"), QUEUE.new(path),
		AVATAR_STORE.new(path, "resident-test", "person-test"),
		AVATAR_QUEUE.new(path, "resident-test", "person-test")]
	for index in stores.size():
		var result: Dictionary = stores[index].call("read")
		check("memory-store-%d-read-propagates-failure" % index,
			result.get("ok") == false and result.get("errorCode") == "AGENT_TEST_RETENTION_FAILED", result)
		if stores[index].has_method("erase_storage"):
			result = stores[index].call("erase_storage")
			check("memory-store-%d-erase-propagates-failure" % index,
				result.get("ok") == false and result.get("errorCode") == "AGENT_TEST_RETENTION_FAILED", result)
	var memory: RefCounted = MEMORY.new({"me": {"resident_id": "resident-test", "attributes": {"name": "test"}}}, sandbox.path_join("owned/memory"))
	memory.set("_memory_path", path)
	var result: Dictionary = memory.call("_clear_resident_storage")
	check("memory-system-cleanup-propagates-failure", result.get("ok") == false and result.get("errorCode") == "AGENT_TEST_RETENTION_FAILED", result)
	check("locked-temp-file-preserved", FileAccess.file_exists(path + ".tmp"))

func hydrate(system: RefCounted, world: RefCounted, bad_after := -1, write_fail_after := -1) -> Dictionary:
	var pending: Dictionary = system.get("_pending_restore")
	var states: Dictionary = pending["resident_states"]
	var index := 0
	for id: String in states:
		var initialization: Dictionary = world.call("get_agent_initialization_by_id", id)
		if index == bad_after:
			initialization["me"] = null
		if index == write_fail_after:
			var blocked_path := String(pending["memory_root"]).path_join(id)
			var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
			blocker.store_string("controlled-file-blocks-resident-directory")
			blocker = null
		var result: Dictionary = system.call("hydrate_restored_resident", initialization, MODEL.new())
		if result.get("ok") != true:
			return result
		index += 1
	return {"ok": true, "count": index}

class RealHydrator extends RefCounted:
	var driver: SceneTree
	var world: RefCounted
	var bad_after := -1
	var write_fail_after := -1
	func hydrate_agent_restore(agent: Object, _config: Dictionary, _ids: Array) -> Dictionary:
		return driver.hydrate(agent, world, bad_after, write_fail_after)

func capture_state(world: RefCounted, agent: RefCounted) -> Dictionary:
	var entries := {}
	var memory_error := FS._inventory(String(agent.get("_memory_root")), entries)
	check("active-memory-inventory", memory_error == OK, int(memory_error))
	return {"worldSnapshot": world.call("create_save_snapshot"),
		"runtimeGeneration": world.call("get_runtime_generation"),
		"worldRevision": world.call("get_world_revision"),
		"agentContext": agent.call("get_save_context"), "agentIds": agent.call("get_active_resident_ids"),
		"runtimeMemoryRoot": agent.get("_memory_root"), "memoryFiles": entries}

func write_snapshot(sandbox: String, name: String, state: Dictionary) -> void:
	var file := FileAccess.open(sandbox.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file = null

func coordinator_restore(sandbox: String) -> void:
	var store: RefCounted = STORE.new()
	store.set("_root", sandbox.path_join("owned/town_session_saves"))
	var agent := new_agent(sandbox, "coordinator")
	var context: Dictionary = spec["context"]
	var config := read_json(String(spec["sessionConfig"]))
	var data := BUILDER.build_from_source("res://world/data/town/source")
	var world: RefCounted = WORLD.new()
	var started: Dictionary = world.call("start", data, config["openingConfig"], config["residentIdentities"])
	check("real-world-start", started.get("ok") == true, started)
	if started.get("ok") != true:
		return
	var runtime := Node.new()
	root.add_child(runtime)
	var gate: RefCounted = GATE.new()
	check("real-gate-configured", gate.call("configure", runtime).get("ok") == true)
	var coordinator: RefCounted = COORDINATOR.new()
	check("real-coordinator-configured", coordinator.call("configure", store, world, agent, gate, {"allowDevelopmentWorld": true}).get("ok") == true)
	var hydrator := RealHydrator.new()
	hydrator.driver = self
	hydrator.world = world
	var result: Dictionary = coordinator.call("restore_revision", context["slot_id"], context["session_id"], 1,
		data, config["residentIdentities"], hydrator)
	check("real-paired-restore", result.get("ok") == true, result)
	check("paired-agent-context", agent.call("get_save_context") == context)
	check("paired-residents-15", agent.call("get_active_resident_ids").get("resident_ids", []).size() == 15)
	if result.get("ok") == true and spec["mode"] != "coordinator":
		var before := capture_state(world, agent)
		write_snapshot(sandbox, "before-state.json", before)
		if spec["mode"] in ["corrupt", "malformed", "incompatible"]:
			store.set("_root", sandbox.path_join("owned/case-town"))
			(agent.get("_save_store") as RefCounted).set("_store_root", sandbox.path_join("owned/case-agent"))
		hydrator.bad_after = 1 if spec["mode"] == "hydrate-abort" else -1
		hydrator.write_fail_after = 1 if spec["mode"] == "write-abort" else -1
		var failed: Dictionary = coordinator.call("restore_revision", context["slot_id"], context["session_id"], 1,
			data, config["residentIdentities"], hydrator)
		check("abnormal-restore-rejected", failed.get("ok") == false and failed.get("errorCode") == spec["expectedErrorCode"], failed)
		var after := capture_state(world, agent)
		write_snapshot(sandbox, "after-state.json", after)
		check("failure-preserves-world-generation-agent-and-memory", before == after)
		check("failure-cancels-pending-restore", (agent.get("_pending_restore") as Dictionary).is_empty())
	check("coordinator-and-gate-released", not bool(coordinator.get("_busy")) and (gate.get("_active") as Dictionary).is_empty())
	var lease: Dictionary = store.call("begin_slot_transaction", context["slot_id"])
	check("lease-reacquirable", lease.get("ok") == true, lease)
	if lease.get("ok") == true:
		check("real-lease-release", store.call("end_slot_transaction", lease["leaseToken"]).get("ok") == true)
	check("paired-close", agent.call("close_game").get("ok") == true)
	world.call("stop")
	runtime.free()
	hydrator.driver = null
	hydrator.world = null
'''


def _retention_fingerprints(root: Path) -> dict[str, str]:
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*") if path.is_file()}


def _audit_retention_journal(journal: Path) -> tuple[list[dict], list[dict]]:
    records = [json.loads(line) for line in journal.read_text("utf-8").splitlines()]
    mismatches = []
    for record in records:
        if record["status"] == "retained":
            target = Path(record["target"])
            actual = _retention_fingerprints(target) if target.is_dir() else {
                ".": hashlib.sha256(target.read_bytes()).hexdigest()}
            expected = {key.removeprefix("./"): value["sha256"]
                        for key, value in record["entries"].items() if value["type"] == "file"}
            if actual != expected:
                mismatches.append({"record": record, "actualHashes": actual})
    if not any(record["status"] == "retained" for record in records):
        mismatches.append({"reason": "No retained operation was recorded"})
    return records, mismatches


def _construct_abnormal_copies(original: Path, owned: Path, mode: str) -> list[str]:
    """Construct explicit copied fixtures; malformed JSON and changed hash are distinct."""
    if mode not in ("corrupt", "malformed", "incompatible"):
        return []
    shutil.copytree(original / "agent_saves", owned / "case-agent")
    shutil.copytree(original / "town_session_saves", owned / "case-town")
    if mode in ("corrupt", "malformed"):
        bad_world = (owned / "case-town/slots/roundtrip-slot-beta6/sessions"
                     / "roundtrip-session-beta6/revisions/00000000000000000001"
                     / "world_snapshot.json")
        if mode == "malformed":
            bad_world.write_bytes(b"controlled-invalid-world-snapshot")
        else:
            value = json.loads(bad_world.read_text("utf-8"))
            value["controlled_test_damage"] = True
            bad_world.write_text(json.dumps(value), encoding="utf-8")
    else:
        bad_slot = owned / "case-agent/roundtrip-slot-beta6/slot.json"
        value = json.loads(bad_slot.read_text("utf-8"))
        value["format_version"] = 999
        bad_slot.write_text(json.dumps(value), encoding="utf-8")
    return ["case-agent", "case-town"]


@pytest.mark.parametrize("mode", ("filesystem", "lease", "agent", "memory", "coordinator",
                                  "corrupt", "malformed", "incompatible",
                                  "hydrate-abort", "write-abort"))
def test_real_cleanup_retention_and_restore(  # pylint: disable=too-many-locals,too-many-statements
    tmp_path: Path, pytestconfig: pytest.Config, godot_executable: Path, mode: str,
    request: pytest.FixtureRequest,
) -> None:
    """Native moves and real participants; original physical deletion is unexecuted."""
    game_root = Path(pytestconfig.rootpath).parent
    original = game_root / "tests/fixtures/historical_saves/beta6"
    original_hashes = _retention_fingerprints(original)
    source_names = ("agent/AgentFileSystem.gd", "agent/AgentSystem.gd",
                    "world/presentation/session/TownSessionSaveStore.gd",
                    "agent/memory/ResidentMemorySystem.gd", "agent/memory/ResidentMemoryStore.gd",
                    "agent/memory/ResidentMemoryEntryStore.gd",
                    "agent/memory/ResidentMemoryInterventionStore.gd",
                    "agent/memory/ResidentEvidenceQueue.gd",
                    "agent/avatar_memory/ResidentAvatarMemoryStore.gd",
                    "agent/avatar_memory/ResidentAvatarEvidenceQueue.gd")
    source_hashes = {name: hashlib.sha256((game_root / name).read_bytes()).hexdigest()
                     for name in source_names}
    sandbox = tmp_path / f"gametest-retention-{mode}"
    owned, retained = sandbox / "owned", sandbox / "retained"
    owned.mkdir(parents=True)
    retained.mkdir()
    journal = sandbox / "retention.jsonl"
    journal.touch()
    for name in ("tree/sub", "collision", "locked", "empty"):
        (owned / name).mkdir(parents=True)
    (owned / "tree/sub/data.bin").write_text("retained-payload", encoding="utf-8")
    (owned / "collision/data.bin").write_bytes(b"collision-evidence")
    locked = owned / "locked/data.bin"
    locked.write_bytes(b"native-lock-evidence")
    if mode == "memory":
        locked = owned / "locked/data.bin.tmp"
        locked.write_bytes(b"native-lock-evidence")
    (owned / "single.bin").write_bytes(b"single-evidence")
    if mode == "filesystem":
        (retained / "00000002").mkdir()
        (retained / "00000002/sentinel.bin").write_bytes(b"no-overwrite")
    foreign = tmp_path / "foreign.bin"
    foreign.write_bytes(b"outside-scope")
    foreign_hash = hashlib.sha256(foreign.read_bytes()).hexdigest()
    if mode == "filesystem":
        link_target = tmp_path / "foreign-directory"
        link_target.mkdir()
        (link_target / "sentinel.bin").write_bytes(b"junction-target-evidence")
        (owned / "linked-tree").mkdir()
        for link in (owned / "junction", owned / "linked-tree/junction"):
            linked = subprocess.run(["cmd.exe", "/c", "mklink", "/J", str(link), str(link_target)],
                                    capture_output=True, check=False)
            assert linked.returncode == 0, linked.stdout + linked.stderr
    shutil.copytree(original / "agent_saves", owned / "agent_saves")
    shutil.copytree(original / "town_session_saves", owned / "town_session_saves")
    copy_names = ["agent_saves", "town_session_saves"]
    copy_names.extend(_construct_abnormal_copies(original, owned, mode))
    copied_hashes = {name: _retention_fingerprints(owned / name) for name in copy_names}
    context = {"slot_id": "roundtrip-slot-beta6", "session_id": "roundtrip-session-beta6",
               "save_revision": 1}
    config = (owned / "town_session_saves/slots/roundtrip-slot-beta6/sessions"
              / "roundtrip-session-beta6/revisions/00000000000000000001/session_config.json")
    spec = tmp_path / "retention-spec.json"
    spec.write_text(json.dumps({"mode": mode, "sandbox": sandbox.as_posix(),
                               "foreign": foreign.as_posix(), "context": context,
                               "sessionConfig": config.as_posix(),
                               "expectedErrorCode": {
                                   "corrupt": "SESSION_SAVE_REFERENCE_HASH_MISMATCH",
                                   "malformed": "SESSION_SAVE_STORE_JSON_INVALID",
                               }.get(mode, "SESSION_CONTINUE_AGENT_PREPARE_FAILED")}),
                    encoding="utf-8")
    driver = tmp_path / "retention-driver.gd"
    driver.write_text(_RETENTION_DRIVER, encoding="utf-8")
    # Windows runner/local Windows use the actual OS sharing rule to fail rename.
    # No fake filesystem result or changed assertion is used for this condition.
    assert sys.platform == "win32", "Native no-share-delete scenario needs Windows"
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                                  ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
                                  ctypes.c_void_p]
    kernel.CreateFileW.restype = ctypes.c_void_p
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.CreateFileW(str(locked), 0x80000000, 3, None, 3, 0x80, None)
    assert handle not in (None, ctypes.c_void_p(-1).value), ctypes.get_last_error()
    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(godot_executable), "--headless", "--path", str(game_root),
             "--log-file", str(tmp_path / "engine.log"), "--script", str(driver),
             "--", str(spec)], capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=90, check=False,
            env={**environ, "AI_TOWN_PROVIDER_TEST_NO_NETWORK": "1"},
        )
    except subprocess.TimeoutExpired as error:
        partial = b"".join(part.encode("utf-8") if isinstance(part, str) else part or b""
                           for part in (error.stdout, error.stderr))
        (tmp_path / "output.log").write_bytes(partial)
        raise
    finally:
        kernel.CloseHandle(handle)
    output = completed.stdout + completed.stderr
    (tmp_path / "output.log").write_text(output, encoding="utf-8")
    results = [json.loads(line.removeprefix("RETENTION_CHECK "))
               for line in completed.stdout.splitlines() if line.startswith("RETENTION_CHECK ")]
    evidence = EvidenceStore(tmp_path / "evidence", "godot-retention", metadata={
        "scope": "retention policy only; original recursive deletion unexecuted",
        "mode": mode, "binding": "private roots to explicitly enrolled absolute fixture copies",
        "caseId": request.node.nodeid,
        "driver": driver.as_posix(), "journal": journal.as_posix(),
        "fixtureSha256": original_hashes, "sourceFileSha256": source_hashes,
    })
    request.node.user_properties.extend([
        ("retentionRunId", evidence.run_id),
        ("retentionEvidencePath", evidence.jsonl_path.as_posix()),
        ("retentionManifestPath", journal.as_posix()),
        ("retentionOutputPath", (tmp_path / "output.log").as_posix()),
    ])
    for result in results:
        evidence.record("retention_assertion", name=result["id"],
                        status="passed" if result["passed"] else "failed", details=result)
    copied_after = {name: _retention_fingerprints(owned / name) for name in copied_hashes}
    isolated = (original_hashes == _retention_fingerprints(original)
                and foreign_hash == hashlib.sha256(foreign.read_bytes()).hexdigest()
                and all(copied_after[name].get(path) == digest
                        for name, entries in copied_hashes.items()
                        for path, digest in entries.items())
                and all(hashlib.sha256((game_root / name).read_bytes()).hexdigest() == digest
                        for name, digest in source_hashes.items()))
    if mode == "filesystem":
        isolated = (isolated and (retained / "00000002/sentinel.bin").read_bytes()
                    == b"no-overwrite"
                    and (tmp_path / "foreign-directory/sentinel.bin").read_bytes()
                    == b"junction-target-evidence")
    evidence.record("isolation_check", name="original-foreign-agent-copy-unchanged",
                    status="passed" if isolated else "failed")
    process_ok = completed.returncode == 0 and "SCRIPT ERROR" not in output and bool(results)
    evidence.record("process_check", name="real-godot-exit-and-script-errors",
                    status="passed" if process_ok else "failed",
                    details={"returnCode": completed.returncode,
                             "outputPath": (tmp_path / "output.log").as_posix()})
    records, mismatches = _audit_retention_journal(journal)
    evidence.record("retention_integrity", name="all-retained-files-match-pre-move-hashes",
                    status="failed" if mismatches else "passed",
                    details={"journalPath": journal.as_posix(), "mismatches": mismatches})
    failures = (sum(not result["passed"] for result in results) + int(not isolated)
                + int(not process_ok) + int(bool(mismatches)))
    evidence.finish(status="failed" if failures else "passed",
                    total=len(results) + 3, passed=len(results) + 3 - failures,
                    failed=failures, skipped=0, other=0,
                    duration_ms=round((time.monotonic() - started) * 1000, 3))
    assert process_ok, output
    assert results and not failures, results
    if mode in ("filesystem", "agent"):
        assert any(record["status"] == "move_failed" for record in records)
