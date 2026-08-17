#!/usr/bin/env python3
"""TownWorldRuntime 架构棘轮。

检查两类只允许收缩的指标：

1. TownWorldRuntime 本体的行数、函数、表面公共函数、顶层状态、信号和长函数数量。
2. world/runtime 子模块对 ``world._私有成员`` 的直接访问次数。

第二类按私有成员名聚合，因此允许在不增加耦合的前提下移动现有辅助代码；任何新成员访问，
或者已有成员访问次数上升，都会失败。完成真实拆分后使用 ``--update`` 收缩基线。
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from guard_common import GUARDS_ROOT, REPO_ROOT, rel


BASELINE_FILE = GUARDS_ROOT / "world_runtime_architecture_baseline.json"
WORLD_RUNTIME = REPO_ROOT / "game/world/runtime/TownWorldRuntime.gd"
RUNTIME_ROOT = REPO_ROOT / "game/world/runtime"
LONG_FUNCTION_MIN_LINES = 120

FUNCTION_RE = re.compile(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)")
TOP_LEVEL_VAR_RE = re.compile(r"^var\s+([A-Za-z_][A-Za-z0-9_]*)")
TOP_LEVEL_SIGNAL_RE = re.compile(r"^signal\s+([A-Za-z_][A-Za-z0-9_]*)")
PRIVATE_WORLD_ACCESS_RE = re.compile(r"\bworld\.(_[A-Za-z_][A-Za-z0-9_]*)")


def _source_lines() -> list[str]:
    return WORLD_RUNTIME.read_text(encoding="utf-8").splitlines()


def _function_ranges(lines: list[str]) -> list[tuple[str, int, int]]:
    starts: list[tuple[str, int]] = []
    for index, line in enumerate(lines):
        match = FUNCTION_RE.match(line)
        if match:
            starts.append((match.group(1), index))
    ranges: list[tuple[str, int, int]] = []
    for index, (name, start) in enumerate(starts):
        end = starts[index + 1][1] if index + 1 < len(starts) else len(lines)
        ranges.append((name, start, end))
    return ranges


def collect_world_metrics() -> dict[str, int]:
    lines = _source_lines()
    functions = _function_ranges(lines)
    return {
        "line_count": len(lines),
        "function_count": len(functions),
        "public_function_count": sum(
            1 for name, _start, _end in functions if not name.startswith("_")
        ),
        "top_level_state_count": sum(
            1 for line in lines if TOP_LEVEL_VAR_RE.match(line)
        ),
        "signal_count": sum(
            1 for line in lines if TOP_LEVEL_SIGNAL_RE.match(line)
        ),
        "long_function_count": sum(
            1
            for _name, start, end in functions
            if end - start >= LONG_FUNCTION_MIN_LINES
        ),
    }


def collect_private_world_accesses() -> Counter[str]:
    accesses: Counter[str] = Counter()
    for path in sorted(RUNTIME_ROOT.rglob("*.gd")):
        if path == WORLD_RUNTIME:
            continue
        text = path.read_text(encoding="utf-8")
        accesses.update(PRIVATE_WORLD_ACCESS_RE.findall(text))
    return accesses


def collect_snapshot() -> dict[str, object]:
    accesses = collect_private_world_accesses()
    return {
        "world_runtime": collect_world_metrics(),
        "private_world_access": {
            "total": sum(accesses.values()),
            "unique_members": len(accesses),
            "members": dict(sorted(accesses.items())),
        },
    }


def load_baseline() -> dict[str, object]:
    return json.loads(BASELINE_FILE.read_text(encoding="utf-8"))


def _failures(
    baseline: dict[str, object],
    current: dict[str, object],
) -> list[str]:
    failures: list[str] = []
    baseline_metrics = baseline["world_runtime"]
    current_metrics = current["world_runtime"]
    assert isinstance(baseline_metrics, dict)
    assert isinstance(current_metrics, dict)
    for metric, limit_value in baseline_metrics.items():
        limit = int(limit_value)
        actual = int(current_metrics.get(metric, 0))
        if actual > limit:
            failures.append(f"TownWorldRuntime {metric}: {actual} > 基线 {limit}")

    baseline_access = baseline["private_world_access"]
    current_access = current["private_world_access"]
    assert isinstance(baseline_access, dict)
    assert isinstance(current_access, dict)
    total_limit = int(baseline_access["total"])
    total_actual = int(current_access["total"])
    if total_actual > total_limit:
        failures.append(
            f"world._私有访问总数: {total_actual} > 基线 {total_limit}"
        )

    baseline_members = baseline_access["members"]
    current_members = current_access["members"]
    assert isinstance(baseline_members, dict)
    assert isinstance(current_members, dict)
    for member, actual_value in current_members.items():
        actual = int(actual_value)
        if member not in baseline_members:
            failures.append(f"新增 world.{member} 私有访问: {actual} 次")
            continue
        limit = int(baseline_members[member])
        if actual > limit:
            failures.append(f"world.{member}: {actual} 次 > 基线 {limit} 次")
    return failures


def cmd_check() -> int:
    if not BASELINE_FILE.exists():
        print(f"架构基线不存在：{rel(BASELINE_FILE)}")
        return 1
    baseline = load_baseline()
    current = collect_snapshot()
    failures = _failures(baseline, current)
    if failures:
        print("TownWorldRuntime 架构棘轮失败（指标只降不升）：")
        for failure in failures:
            print(f"  {failure}")
        return 1
    metrics = current["world_runtime"]
    access = current["private_world_access"]
    assert isinstance(metrics, dict)
    assert isinstance(access, dict)
    print(
        "TownWorldRuntime 架构棘轮通过："
        f"lines={metrics['line_count']} functions={metrics['function_count']} "
        f"states={metrics['top_level_state_count']} "
        f"private_accesses={access['total']}。"
    )
    return 0


def _apply_private_access_renames(
    baseline: dict[str, object],
    current: dict[str, object],
    renames: list[str],
) -> list[str]:
    errors: list[str] = []
    baseline_access = baseline["private_world_access"]
    current_access = current["private_world_access"]
    assert isinstance(baseline_access, dict)
    assert isinstance(current_access, dict)
    baseline_members = baseline_access["members"]
    current_members = current_access["members"]
    assert isinstance(baseline_members, dict)
    assert isinstance(current_members, dict)
    for rename in renames:
        if rename.count("=") != 1:
            errors.append(f"私有访问迁移格式错误：{rename}")
            continue
        old_member, new_member = rename.split("=", 1)
        if not old_member.startswith("_") or not new_member.startswith("_"):
            errors.append(f"私有访问迁移必须使用 _成员名：{rename}")
            continue
        if old_member not in baseline_members:
            errors.append(f"私有访问旧成员不在基线中：{old_member}")
            continue
        if new_member in baseline_members:
            errors.append(f"私有访问新成员已在基线中：{new_member}")
            continue
        if int(current_members.get(old_member, 0)) != 0:
            errors.append(f"私有访问旧成员尚未清零：world.{old_member}")
            continue
        old_limit = int(baseline_members[old_member])
        new_count = int(current_members.get(new_member, 0))
        if new_count > old_limit:
            errors.append(
                f"私有访问迁移增加次数：world.{new_member} "
                f"{new_count} > 旧基线 {old_limit}"
            )
            continue
        del baseline_members[old_member]
        baseline_members[new_member] = old_limit
    return errors


def cmd_update(private_access_renames: list[str]) -> int:
    current = collect_snapshot()
    if not BASELINE_FILE.exists():
        if private_access_renames:
            print("首次建立基线时不能指定私有访问迁移。")
            return 1
        baseline = {"version": 1, **current}
    else:
        baseline = load_baseline()
        rename_errors = _apply_private_access_renames(
            baseline,
            current,
            private_access_renames,
        )
        if rename_errors:
            print("私有访问迁移失败：")
            for error in rename_errors:
                print(f"  {error}")
            return 1
        failures = _failures(baseline, current)
        if failures:
            print("当前指标超过旧基线，拒绝上调：")
            for failure in failures:
                print(f"  {failure}")
            return 1
        baseline_metrics = baseline["world_runtime"]
        current_metrics = current["world_runtime"]
        assert isinstance(baseline_metrics, dict)
        assert isinstance(current_metrics, dict)
        for metric, current_value in current_metrics.items():
            baseline_metrics[metric] = min(
                int(baseline_metrics.get(metric, current_value)),
                int(current_value),
            )
        baseline_access = baseline["private_world_access"]
        current_access = current["private_world_access"]
        assert isinstance(baseline_access, dict)
        assert isinstance(current_access, dict)
        baseline_access["total"] = min(
            int(baseline_access["total"]),
            int(current_access["total"]),
        )
        baseline_access["unique_members"] = int(current_access["unique_members"])
        baseline_members = baseline_access["members"]
        current_members = current_access["members"]
        assert isinstance(baseline_members, dict)
        assert isinstance(current_members, dict)
        baseline_access["members"] = {
            member: min(int(baseline_members[member]), int(count))
            for member, count in current_members.items()
        }

    BASELINE_FILE.write_text(
        json.dumps(baseline, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"TownWorldRuntime 架构基线已更新：{rel(BASELINE_FILE)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true")
    group.add_argument("--update", action="store_true")
    parser.add_argument(
        "--rename-private-access",
        action="append",
        default=[],
        metavar="OLD=NEW",
        help="只在 --update 时登记次数不增加的私有成员迁移",
    )
    args = parser.parse_args()
    if args.rename_private_access and not args.update:
        parser.error("--rename-private-access 必须与 --update 一起使用")
    return (
        cmd_update(args.rename_private_access)
        if args.update
        else cmd_check()
    )


if __name__ == "__main__":
    raise SystemExit(main())
