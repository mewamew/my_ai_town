#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from persistence_change_check import check_changes


class PersistenceChangeCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in (
            "game/tests/fixtures/historical_saves/catalog.json",
            "game/tests/persistence_story_test.gd",
            "docs/存档迁移手册.md",
        ):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("{}", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_sensitive_change_requires_declaration(self) -> None:
        errors = check_changes(
            self.root,
            {"game/world/runtime/persistence/Codec.gd"},
        )
        self.assertIn("缺少", errors[0])

    def test_complete_migration_declaration_passes(self) -> None:
        declaration = "docs/persistence-changes/example.json"
        path = self.root / declaration
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self._declaration()), encoding="utf-8")
        changed = {
            "game/world/runtime/persistence/Codec.gd",
            declaration,
            "game/tests/fixtures/historical_saves/catalog.json",
            "game/tests/persistence_story_test.gd",
            "docs/存档迁移手册.md",
        }
        self.assertEqual(check_changes(self.root, changed), [])

    def test_migration_requires_changed_sample(self) -> None:
        declaration = "docs/persistence-changes/example.json"
        path = self.root / declaration
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self._declaration()), encoding="utf-8")
        errors = check_changes(
            self.root,
            {
                "game/world/runtime/persistence/Codec.gd",
                declaration,
                "game/tests/persistence_story_test.gd",
                "docs/存档迁移手册.md",
            },
        )
        self.assertTrue(any("更新历史样本" in error for error in errors))

    def test_unrelated_change_needs_no_declaration(self) -> None:
        self.assertEqual(check_changes(self.root, {"README.md"}), [])

    @staticmethod
    def _declaration() -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "decision": "migration",
            "summary": "升级存档字段。",
            "affectedModules": ["world_snapshot"],
            "migrationIds": ["example-migration"],
            "samples": ["game/tests/fixtures/historical_saves/catalog.json"],
            "tests": ["game/tests/persistence_story_test.gd"],
            "docs": ["docs/存档迁移手册.md"],
        }


if __name__ == "__main__":
    unittest.main()
