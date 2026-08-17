#!/usr/bin/env python3
"""Ensure literal GDScript preload targets exist in the Godot project."""

from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard_common import REPO_ROOT  # noqa: E402


GAME_ROOT = REPO_ROOT / "game"
PRELOAD_CALL_RE = re.compile(r"preload\s*\(")


def preload_argument_bodies(source: str) -> list[str]:
    """Return balanced argument text for every preload call in source."""
    bodies: list[str] = []
    for match in PRELOAD_CALL_RE.finditer(source):
        depth = 1
        quote: str | None = None
        escaped = False
        index = match.end()
        while index < len(source):
            character = source[index]
            if quote is not None:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    quote = None
            elif character in ("'", '"'):
                quote = character
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    bodies.append(source[match.end() : index])
                    break
            index += 1
    return bodies


def literal_preload_path(arguments: str) -> str | None:
    """Resolve a preload made from quoted strings joined with ``+``.

    Godot accepts both a trailing comma and compile-time string concatenation
    in preload calls. Expressions containing variables or method calls are
    intentionally ignored because their final path cannot be resolved safely
    by this static check.
    """
    pieces: list[str] = []
    index = 0
    while index < len(arguments):
        while index < len(arguments) and arguments[index].isspace():
            index += 1
        if index >= len(arguments):
            break
        if arguments[index] in ("'", '"'):
            quote = arguments[index]
            start = index
            index += 1
            escaped = False
            while index < len(arguments):
                character = arguments[index]
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    index += 1
                    break
                index += 1
            else:
                return None
            try:
                value = ast.literal_eval(arguments[start:index])
            except (SyntaxError, ValueError):
                return None
            if not isinstance(value, str):
                return None
            pieces.append(value)
        else:
            return None
        while index < len(arguments) and arguments[index].isspace():
            index += 1
        if index >= len(arguments):
            break
        if arguments[index] == "+":
            index += 1
            continue
        if arguments[index] == "," and not arguments[index + 1 :].strip():
            break
        return None
    path = "".join(pieces)
    return path if path.startswith("res://") else None


def tracked_gdscript_paths() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--", "game"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [
        REPO_ROOT / line
        for line in result.stdout.splitlines()
        if line.endswith(".gd") and (REPO_ROOT / line).is_file()
    ]


def main() -> int:
    checked = 0
    failures: list[str] = []
    for source_path in tracked_gdscript_paths():
        source = source_path.read_text(encoding="utf-8")
        for arguments in preload_argument_bodies(source):
            resource_path = literal_preload_path(arguments)
            if resource_path is None:
                continue
            checked += 1
            disk_path = GAME_ROOT / resource_path.removeprefix("res://")
            if not disk_path.is_file():
                relative_source = source_path.relative_to(REPO_ROOT)
                failures.append(f"{relative_source}: {resource_path}")

    if failures:
        print("GDScript preload 资源检查失败，以下目标文件不存在：")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print(f"PRELOAD_RESOURCE_CHECK_PASS references={checked}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
