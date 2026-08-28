#!/usr/bin/env python3
"""Require an explicit compatibility declaration for persistence changes."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DECLARATION_PREFIX = "docs/persistence-changes/"
SENSITIVE_PREFIXES = (
    "game/world/data/",
    "game/world/runtime/persistence/",
    "game/world/presentation/session/",
    "game/agent/lifecycle/",
    "game/agent/memory/",
    "game/agent/avatar_memory/",
    "game/assets/characters/",
)
SENSITIVE_FILES = {
    "VERSION",
    "game/world/presentation/game_flow/GameFlowHost.gd",
    "game/ui/startup/StartupLoadGameScreen.gd",
    "game/ui/new_game_overwrite/NewGameOverwriteScreen.gd",
}
VALID_DECISIONS = {"migration", "no_migration"}


def changed_files(base_ref: str | None) -> set[str]:
    commands = (
        ["git", "-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=ACMR", f"{base_ref}...HEAD"]
        if base_ref
        else ["git", "-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"]
    )
    tracked = subprocess.run(
        commands,
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    staged = subprocess.run(
        ["git", "-c", "core.quotePath=false", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    untracked = subprocess.run(
        ["git", "-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    return {path for path in tracked + staged + untracked if path}


def is_sensitive(path: str) -> bool:
    return path in SENSITIVE_FILES or path.startswith(SENSITIVE_PREFIXES)


def check_changes(repo_root: Path, paths: set[str]) -> list[str]:
    sensitive = sorted(path for path in paths if is_sensitive(path))
    if not sensitive:
        return []
    declarations = sorted(
        path
        for path in paths
        if path.startswith(DECLARATION_PREFIX) and path.endswith(".json")
    )
    if not declarations:
        return [
            "持久化相关文件已修改，但缺少 docs/persistence-changes/*.json 声明。"
        ]
    errors: list[str] = []
    for declaration in declarations:
        errors.extend(validate_declaration(repo_root, declaration, paths))
    return errors


def validate_declaration(
    repo_root: Path,
    relative_path: str,
    changed: set[str],
) -> list[str]:
    label = f"[{relative_path}]"
    path = repo_root / relative_path
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"{label} 无法读取：{error}"]
    if not isinstance(value, dict):
        return [f"{label} 顶层必须是对象。"]
    errors: list[str] = []
    decision = value.get("decision")
    if value.get("schemaVersion") != 1:
        errors.append(f"{label} schemaVersion 必须为 1。")
    if decision not in VALID_DECISIONS:
        errors.append(f"{label} decision 必须是 migration 或 no_migration。")
    if not isinstance(value.get("summary"), str) or not value["summary"].strip():
        errors.append(f"{label} summary 不能为空。")
    modules = value.get("affectedModules")
    if not _non_empty_strings(modules):
        errors.append(f"{label} affectedModules 必须列出受影响模块。")
    migration_ids = value.get("migrationIds")
    if not isinstance(migration_ids, list) or any(
        not isinstance(item, str) or not item.strip() for item in migration_ids
    ):
        errors.append(f"{label} migrationIds 必须是字符串数组。")
    elif decision == "migration" and not migration_ids:
        errors.append(f"{label} migration 决策必须登记 migrationIds。")
    elif decision == "no_migration" and migration_ids:
        errors.append(f"{label} no_migration 决策不能登记 migrationIds。")

    references = {
        "samples": ("game/tests/fixtures/",),
        "tests": ("game/tests/", "tools/"),
        "docs": ("docs/",),
    }
    for field, prefixes in references.items():
        items = value.get(field)
        if not _non_empty_strings(items):
            errors.append(f"{label} {field} 必须至少列出一个文件。")
            continue
        for item in items:
            if not item.startswith(prefixes) or not (repo_root / item).is_file():
                errors.append(f"{label} {field} 引用无效：{item}")
        if field in {"tests", "docs"} and not any(item in changed for item in items):
            errors.append(f"{label} {field} 至少有一个引用文件必须在本次修改中更新。")
    if decision == "migration" and not any(
        item in changed for item in value.get("samples", [])
    ):
        errors.append(f"{label} migration 决策必须在本次修改中更新历史样本。")
    return errors


def _non_empty_strings(value: object) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(isinstance(item, str) and bool(item.strip()) for item in value)
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-ref")
    args = parser.parse_args()
    errors = check_changes(REPO_ROOT, changed_files(args.base_ref))
    if errors:
        for error in errors:
            print(f"PERSISTENCE_CHANGE_CHECK_FAIL: {error}")
        return 1
    print("PERSISTENCE_CHANGE_CHECK_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
