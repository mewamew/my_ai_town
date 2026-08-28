#!/usr/bin/env python3
"""Verify Issue #146 historical save fixtures and their provenance catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIXTURE_ROOT = REPO_ROOT / "game/tests/fixtures/historical_saves"
CATALOG_FILE = "catalog.json"
FORBIDDEN_FILE_NAMES = {
    "logs",
    "objectdb_snapshots",
    "provider_credentials.enc",
    "web_device_id",
}
EPHEMERAL_DIRECTORIES = {"slot_leases", "_claims"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        # Godot 4.7 writes the activity reservation separator U+001F without
        # JSON escaping. Historical bytes must stay untouched, so inspection
        # uses Python's compatible non-strict mode and verifies that edge below.
        value = json.load(handle, strict=False)
    if not isinstance(value, dict):
        raise ValueError(f"{path} 顶层必须是对象")
    return value


def fixture_integrity(fixture_root: Path) -> dict[str, Any]:
    files: dict[str, str] = {}
    total_bytes = 0
    for path in sorted(candidate for candidate in fixture_root.rglob("*") if candidate.is_file()):
        relative = path.relative_to(fixture_root).as_posix()
        files[relative] = sha256_file(path)
        total_bytes += path.stat().st_size
    tree_input = "".join(f"{digest}  {relative}\n" for relative, digest in files.items())
    return {
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "treeSha256": hashlib.sha256(tree_input.encode("utf-8")).hexdigest(),
        "files": files,
    }


class FixtureVerifier:
    def __init__(self, fixture_root: Path, generator: dict[str, Any]) -> None:
        self.fixture_root = fixture_root
        self.generator = generator
        self.errors: list[str] = []

    def expect(self, condition: bool, message: str) -> None:
        if not condition:
            self.errors.append(message)

    def verify(self, fixture: dict[str, Any]) -> None:
        fixture_id = str(fixture.get("id", ""))
        root = self.fixture_root / fixture_id
        label = f"[{fixture_id}]"
        self.expect(root.is_dir(), f"{label} 样本目录不存在")
        if not root.is_dir():
            return

        self._verify_source_provenance(fixture, label)
        actual_integrity = fixture_integrity(root)
        expected_integrity = fixture.get("integrity", {})
        self.expect(
            actual_integrity == expected_integrity,
            f"{label} 文件集合或 SHA-256 与目录不符",
        )
        self._verify_no_excluded_data(root, label)
        self._verify_storage_contract(root, fixture, label)

    def _verify_source_provenance(self, fixture: dict[str, Any], label: str) -> None:
        source_ref = str(fixture.get("sourceRef", ""))
        expected_commit = str(fixture.get("sourceCommit", ""))
        expected_version = str(fixture.get("releaseVersion", ""))
        try:
            actual_commit = subprocess.run(
                ["git", "-C", str(REPO_ROOT), "rev-parse", source_ref],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            source_version = subprocess.run(
                ["git", "-C", str(REPO_ROOT), "show", f"{source_ref}:VERSION"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            source_test_path = str(
                fixture.get("sourceTestPath", self.generator.get("testPath", ""))
            )
            source_test = subprocess.run(
                [
                    "git",
                    "-C",
                    str(REPO_ROOT),
                    "show",
                    f"{source_ref}:{source_test_path}",
                ],
                check=True,
                capture_output=True,
            ).stdout
        except subprocess.CalledProcessError:
            self.errors.append(f"{label} 无法读取 Git 来源 {source_ref}")
            return
        expected_test_sha256 = str(
            fixture.get("sourceTestSha256", self.generator.get("testSha256", ""))
        )
        self.expect(actual_commit == expected_commit, f"{label} Git 提交与登记不符")
        self.expect(source_version == expected_version, f"{label} VERSION 与登记不符")
        self.expect(
            hashlib.sha256(source_test).hexdigest() == expected_test_sha256,
            f"{label} 发行版生成测试与已审计版本不符",
        )

    def _verify_no_excluded_data(self, root: Path, label: str) -> None:
        for path in root.rglob("*"):
            if path.is_file():
                self.expect(
                    path.name not in FORBIDDEN_FILE_NAMES,
                    f"{label} 含排除项：{path.name}",
                )
            if path.is_dir() and path.name in EPHEMERAL_DIRECTORIES:
                self.expect(
                    not any(candidate.is_file() for candidate in path.rglob("*")),
                    f"{label} 临时目录中仍有文件：{path.relative_to(root)}",
                )
            self.expect(
                not path.name.endswith((".tmp", ".bak", ".claim")),
                f"{label} 含临时文件：{path.relative_to(root)}",
            )

    def _verify_storage_contract(
        self,
        root: Path,
        fixture: dict[str, Any],
        label: str,
    ) -> None:
        slot_id = str(fixture.get("slotId", ""))
        session_id = str(fixture.get("sessionId", ""))
        revision = int(fixture.get("saveRevision", 0))
        revision_text = f"{revision:020d}"
        world_root = root / "town_session_saves"
        slot_root = world_root / "slots" / slot_id
        revision_root = slot_root / "sessions" / session_id / "revisions" / revision_text
        manifest_path = slot_root / "manifests" / f"{revision_text}.json"

        required_paths = [
            root / "town_startup_profile.json",
            root / "town_custom_resident_library.json",
            root / "audio_settings.cfg",
            root / "player_settings.cfg",
            manifest_path,
            revision_root / "world_snapshot.json",
            revision_root / "world_log_snapshot.json",
            revision_root / "session_config.json",
            root / "agent_saves" / slot_id / "slot.json",
        ]
        for path in required_paths:
            self.expect(path.is_file(), f"{label} 缺少 {path.relative_to(root)}")
        if any(not path.is_file() for path in required_paths):
            return

        manifest = load_json(manifest_path)
        scenario = fixture.get("scenario", {})
        resident_count = int(scenario.get("residentCount", 0))
        self.expect(manifest.get("schema") == "town-session-save-manifest", f"{label} manifest schema 错误")
        self.expect(manifest.get("schema_version") == 3, f"{label} manifest 版本错误")
        self.expect(manifest.get("state") == "published", f"{label} manifest 未发布")
        self.expect(manifest.get("slot_id") == slot_id, f"{label} manifest slot_id 错误")
        self.expect(manifest.get("session_id") == session_id, f"{label} manifest session_id 错误")
        self.expect(manifest.get("save_revision") == revision, f"{label} manifest 修订号错误")
        manifest_resident_ids = manifest.get("resident_ids", [])
        self.expect(
            len(manifest_resident_ids) == resident_count,
            f"{label} manifest 居民数错误",
        )

        components = manifest.get("components", {})
        self._verify_manifest_reference(
            world_root,
            components.get("world", {}),
            "snapshot_ref",
            "snapshot_sha256",
            label,
        )
        self._verify_manifest_reference(
            world_root,
            components.get("world_log", {}),
            "snapshot_ref",
            "snapshot_sha256",
            label,
        )
        self._verify_direct_reference(
            world_root,
            str(manifest.get("session_config_ref", "")),
            str(manifest.get("session_config_sha256", "")),
            label,
        )

        world = load_json(revision_root / "world_snapshot.json")
        state = world.get("state", {})
        expected_world = fixture.get("world", {})
        self.expect(world.get("schemaVersion") == 2, f"{label} World 版本错误")
        self.expect(world.get("worldDataVersion") == 4, f"{label} worldDataVersion 错误")
        self.expect(isinstance(state, dict), f"{label} World state 不是对象")
        if isinstance(state, dict):
            self.expect(len(state) == expected_world.get("sectionCount"), f"{label} World 区段数错误")
            activity = state.get("activityRuntime", {})
            self.expect(
                activity.get("sourceFingerprint") == expected_world.get("activityFingerprint"),
                f"{label} 活动指纹错误",
            )
            tasks = state.get("workTasks", {}).get("tasks", [])
            task_states = Counter(str(task.get("state", "")) for task in tasks)
            self.expect(
                dict(sorted(task_states.items())) == scenario.get("workTaskStates"),
                f"{label} 工作任务状态覆盖与目录不符",
            )

        session_config = load_json(revision_root / "session_config.json")
        self.expect(session_config.get("sessionId") == session_id, f"{label} session config 会话错误")

        profile = load_json(root / "town_startup_profile.json")
        self.expect(profile.get("schemaVersion") == 2, f"{label} profile 版本错误")
        self.expect(profile.get("lastPlayedSlotId") == slot_id, f"{label} profile 未指向样本槽位")
        library = load_json(root / "town_custom_resident_library.json")
        candidates = library.get("candidates", [])
        custom_resident_id = str(scenario.get("customResidentId", "fixture-custom-resident"))
        self.expect(library.get("schemaVersion") == 1, f"{label} 自定义居民库版本错误")
        self.expect(
            any(candidate.get("residentId") == custom_resident_id for candidate in candidates),
            f"{label} 自定义居民样本不存在",
        )

        if bool(scenario.get("customResidentInSession", False)):
            world_resident_ids = {
                str(resident.get("residentId", ""))
                for resident in state.get("residents", [])
                if isinstance(resident, dict)
            }
            binding_ids = {
                str(binding.get("residentId", ""))
                for binding in session_config.get("residentBindings", [])
                if isinstance(binding, dict)
            }
            self.expect(custom_resident_id in manifest_resident_ids, f"{label} manifest 缺少自定义居民")
            self.expect(custom_resident_id in world_resident_ids, f"{label} World 缺少自定义居民")
            self.expect(custom_resident_id in binding_ids, f"{label} session config 缺少自定义居民")

        photo_root = root / "town_conversation_photos" / slot_id / session_id
        photos = sorted(photo_root.glob("chat-photo-sha256-*.bin"))
        expected_photo_count = int(scenario.get("expectedPhotoCount", 1))
        self.expect(len(photos) == expected_photo_count, f"{label} 已提交照片数错误")
        for photo in photos:
            expected_name = f"chat-photo-sha256-{sha256_file(photo)}.bin"
            self.expect(photo.name == expected_name, f"{label} 照片内容寻址错误")

        self._verify_agent_revision(root, fixture, label)
        self._verify_scenario_edges(root, fixture, label)
        expected_beta6 = fixture.get("expectedBeta6", {})
        self.expect(expected_beta6.get("targetRelease") == "0.1.0-beta.6", f"{label} 缺少 beta6 预期结果")
        self.expect(expected_beta6.get("worldSectionCount") == 27, f"{label} beta6 目标区段数错误")

    def _verify_manifest_reference(
        self,
        root: Path,
        component: Any,
        reference_key: str,
        sha_key: str,
        label: str,
    ) -> None:
        if not isinstance(component, dict):
            self.errors.append(f"{label} manifest 组件不是对象")
            return
        self._verify_direct_reference(
            root,
            str(component.get(reference_key, "")),
            str(component.get(sha_key, "")),
            label,
        )

    def _verify_direct_reference(
        self,
        root: Path,
        reference: str,
        expected_sha256: str,
        label: str,
    ) -> None:
        path = root / reference
        self.expect(path.is_file(), f"{label} 引用不存在：{reference}")
        if path.is_file():
            self.expect(sha256_file(path) == expected_sha256, f"{label} 引用哈希错误：{reference}")

    def _verify_agent_revision(
        self,
        root: Path,
        fixture: dict[str, Any],
        label: str,
    ) -> None:
        slot_id = str(fixture.get("slotId", ""))
        session_id = str(fixture.get("sessionId", ""))
        revision = int(fixture.get("saveRevision", 0))
        agent_root = root / "agent_saves" / slot_id / "sessions" / session_id / "revisions" / str(revision)
        snapshot_path = agent_root / "snapshot.json"
        self.expect(snapshot_path.is_file(), f"{label} 缺少 Agent 修订清单")
        if not snapshot_path.is_file():
            return
        snapshot = load_json(snapshot_path)
        residents = snapshot.get("residents", [])
        scenario = fixture.get("scenario", {})
        resident_count = int(scenario.get("residentCount", 0))
        self.expect(snapshot.get("format_version") == 3, f"{label} Agent 版本错误")
        self.expect(snapshot.get("resident_count") == resident_count, f"{label} Agent 居民数错误")
        self.expect(len(residents) == resident_count, f"{label} Agent 居民条目数错误")
        resident_ids = {
            str(resident.get("resident_id", ""))
            for resident in residents
            if isinstance(resident, dict)
        }
        resident_set_path = agent_root / "resident_set.json"
        self.expect(resident_set_path.is_file(), f"{label} 缺少 Agent resident_set")
        if resident_set_path.is_file():
            resident_set = load_json(resident_set_path)
            self.expect(
                set(resident_set.get("resident_ids", [])) == resident_ids,
                f"{label} Agent resident_set 与修订清单不一致",
            )
        if bool(scenario.get("customResidentInSession", False)):
            custom_resident_id = str(scenario.get("customResidentId", ""))
            self.expect(custom_resident_id in resident_ids, f"{label} Agent 缺少自定义居民")
        for resident in residents:
            path = agent_root / str(resident.get("file", ""))
            self.expect(path.is_file(), f"{label} Agent 载荷不存在：{path.name}")
            if path.is_file():
                self.expect(path.stat().st_size == resident.get("byte_length"), f"{label} Agent 字节数错误：{path.name}")
                self.expect(sha256_file(path) == resident.get("sha256"), f"{label} Agent 哈希错误：{path.name}")

    def _verify_scenario_edges(
        self,
        root: Path,
        fixture: dict[str, Any],
        label: str,
    ) -> None:
        scenario = fixture.get("scenario", {})
        minimum_path_length = int(scenario.get("minimumRelativePathLength", 0))
        if minimum_path_length > 0:
            relative_paths = [
                path.relative_to(root).as_posix()
                for path in root.rglob("*")
                if path.is_file()
            ]
            maximum_path_length = max(map(len, relative_paths), default=0)
            self.expect(
                maximum_path_length == int(scenario.get("maxRelativePathLength", 0)),
                f"{label} 最长相对路径与目录不符",
            )
            self.expect(
                maximum_path_length > minimum_path_length,
                f"{label} 未形成超过 {minimum_path_length} 字符的相对路径",
            )

        lifecycle = scenario.get("activityLifecycle", {})
        if not isinstance(lifecycle, dict) or not lifecycle:
            return
        slot_id = str(fixture.get("slotId", ""))
        session_id = str(fixture.get("sessionId", ""))
        revision_root = (
            root
            / "town_session_saves"
            / "slots"
            / slot_id
            / "sessions"
            / session_id
            / "revisions"
        )
        active_path = revision_root / f"{int(lifecycle.get('activeRevision', 0)):020d}" / "world_snapshot.json"
        settled_path = revision_root / f"{int(lifecycle.get('settledRevision', 0)):020d}" / "world_snapshot.json"
        self.expect(active_path.is_file(), f"{label} 缺少活动进行中修订")
        self.expect(settled_path.is_file(), f"{label} 缺少活动结算后修订")
        if not active_path.is_file() or not settled_path.is_file():
            return

        active = load_json(active_path).get("state", {}).get("activityRuntime", {})
        settled = load_json(settled_path).get("state", {}).get("activityRuntime", {})
        activity_id = str(lifecycle.get("activityId", ""))
        active_executions = [
            execution
            for execution in active.get("executions", [])
            if execution.get("activityId") == activity_id
        ]
        settled_executions = [
            execution
            for execution in settled.get("executions", [])
            if execution.get("activityId") == activity_id
        ]
        self.expect(len(active_executions) == 1, f"{label} 进行中活动条目错误")
        self.expect(len(active.get("reservations", [])) == 1, f"{label} 活动预约条目错误")
        self.expect(len(settled_executions) == 1, f"{label} 已结算活动条目错误")
        self.expect(not settled.get("reservations", []), f"{label} 结算后仍保留活动预约")
        if active_executions:
            execution = active_executions[0]
            self.expect(execution.get("status") == "executing", f"{label} 活动不是执行中状态")
            self.expect(execution.get("effectCommit") is False, f"{label} 进行中活动提前提交效果")
            self.expect(int(execution.get("remainingTicks", 0)) > 0, f"{label} 进行中活动没有剩余时长")
        reservations = active.get("reservations", [])
        if reservations:
            reservation_key = str(reservations[0].get("reservationKey", ""))
            self.expect(
                reservation_key == str(lifecycle.get("reservationKey", "")),
                f"{label} 活动预约键错误",
            )
            self.expect(b"\x1f" in active_path.read_bytes(), f"{label} 未保留发行版 U+001F 原始字节")
        if settled_executions:
            execution = settled_executions[0]
            self.expect(execution.get("status") == "completed", f"{label} 活动未结算")
            self.expect(execution.get("effectCommit") is True, f"{label} 结算效果未提交")
            self.expect(
                execution.get("committedEffects") == lifecycle.get("settledEffects"),
                f"{label} 已结算效果与目录不符",
            )


def refresh_fixture_metadata(fixture_root: Path, fixture: dict[str, Any]) -> None:
    manifests = [
        load_json(path)
        for path in fixture_root.glob("town_session_saves/slots/*/manifests/*.json")
    ]
    if not manifests:
        raise FileNotFoundError(f"样本没有已发布 manifest：{fixture_root}")
    manifest = max(manifests, key=lambda value: int(value.get("save_revision", 0)))
    slot_id = str(manifest.get("slot_id", ""))
    session_id = str(manifest.get("session_id", ""))
    revision = int(manifest.get("save_revision", 0))
    fixture["slotId"] = slot_id
    fixture["sessionId"] = session_id
    fixture["saveRevision"] = revision

    revision_root = (
        fixture_root
        / "town_session_saves"
        / "slots"
        / slot_id
        / "sessions"
        / session_id
        / "revisions"
        / f"{revision:020d}"
    )
    state = load_json(revision_root / "world_snapshot.json").get("state", {})
    fixture["world"] = {
        "sectionCount": len(state),
        "activityFingerprint": state.get("activityRuntime", {}).get("sourceFingerprint", ""),
    }
    scenario = fixture.setdefault("scenario", {})
    scenario["residentCount"] = len(manifest.get("resident_ids", []))
    task_states = Counter(
        str(task.get("state", ""))
        for task in state.get("workTasks", {}).get("tasks", [])
    )
    scenario["workTaskStates"] = dict(sorted(task_states.items()))

    if bool(scenario.get("customResidentInSession", False)):
        library = load_json(fixture_root / "town_custom_resident_library.json")
        custom_ids = [
            str(candidate.get("residentId", ""))
            for candidate in library.get("candidates", [])
            if candidate.get("source") == "custom"
        ]
        if len(custom_ids) != 1:
            raise ValueError(f"自定义居民样本必须恰好一名：{fixture_root}")
        scenario["customResidentId"] = custom_ids[0]

    lifecycle = scenario.get("activityLifecycle", {})
    if isinstance(lifecycle, dict) and lifecycle:
        active_revision = int(lifecycle.get("activeRevision", 0))
        settled_revision = int(lifecycle.get("settledRevision", 0))
        active_path = revision_root.parent / f"{active_revision:020d}" / "world_snapshot.json"
        settled_path = revision_root.parent / f"{settled_revision:020d}" / "world_snapshot.json"
        active_runtime = load_json(active_path).get("state", {}).get("activityRuntime", {})
        settled_runtime = load_json(settled_path).get("state", {}).get("activityRuntime", {})
        reservations = active_runtime.get("reservations", [])
        lifecycle["reservationKey"] = str(reservations[0].get("reservationKey", ""))
        activity_id = str(lifecycle.get("activityId", ""))
        settled_executions = [
            execution
            for execution in settled_runtime.get("executions", [])
            if execution.get("activityId") == activity_id
        ]
        lifecycle["settledEffects"] = settled_executions[0].get("committedEffects", {})

    if int(scenario.get("minimumRelativePathLength", 0)) > 0:
        scenario["maxRelativePathLength"] = max(
            (
                len(path.relative_to(fixture_root).as_posix())
                for path in fixture_root.rglob("*")
                if path.is_file()
            ),
            default=0,
        )


def refresh_catalog(root: Path, catalog: dict[str, Any]) -> None:
    for fixture in catalog.get("fixtures", []):
        fixture_root = root / str(fixture.get("id", ""))
        if not fixture_root.is_dir():
            raise FileNotFoundError(f"样本目录不存在：{fixture_root}")
        refresh_fixture_metadata(fixture_root, fixture)
        fixture["integrity"] = fixture_integrity(fixture_root)
    with (root / CATALOG_FILE).open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=DEFAULT_FIXTURE_ROOT)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    catalog_path = args.root / CATALOG_FILE
    catalog = load_json(catalog_path)
    if args.refresh:
        refresh_catalog(args.root, catalog)
        catalog = load_json(catalog_path)

    verifier = FixtureVerifier(args.root, catalog.get("generator", {}))
    fixtures = catalog.get("fixtures", [])
    verifier.expect(catalog.get("schemaVersion") == 1, "catalog schemaVersion 错误")
    fixture_ids = {str(fixture.get("id", "")) for fixture in fixtures}
    verifier.expect(
        {f"beta{version}" for version in range(1, 7)}.issubset(fixture_ids),
        "必须登记 beta1 至 beta6 六份基础样本",
    )
    verifier.expect(
        {"beta5-activity-lifecycle", "beta5-long-path"}.issubset(fixture_ids),
        "必须登记活动生命周期和长路径边界样本",
    )
    for fixture in fixtures:
        verifier.verify(fixture)
    if verifier.errors:
        for error in verifier.errors:
            print(f"HISTORICAL_SAVE_FIXTURE_FAIL: {error}", file=sys.stderr)
        return 1
    total_files = sum(int(fixture.get("integrity", {}).get("fileCount", 0)) for fixture in fixtures)
    print(f"HISTORICAL_SAVE_FIXTURES_PASS fixtures={len(fixtures)} files={total_files}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
