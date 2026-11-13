#!/usr/bin/env python3
"""Testy tools/changelog.py i tools/version.py (bez sieci).
Uruchomienie: python3 -m unittest discover -s tools -p "test_*.py"
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import changelog  # noqa: E402
import version  # noqa: E402


def pr(number: int, title: str, branch: str, merged: str = "2026-11-13T10:00:00Z", labels: list[str] | None = None) -> dict:
    return {
        "number": number,
        "title": title,
        "head": {"ref": branch},
        "merged_at": merged,
        "labels": [{"name": n} for n in (labels or [])],
    }


class CategoryTest(unittest.TestCase):
    def test_branch_prefix(self) -> None:
        self.assertEqual(changelog.category(pr(1, "a", "feat/etap-3-budynki")), "Dodane")
        self.assertEqual(changelog.category(pr(1, "a", "fix/android-etc2-astc")), "Naprawione")
        self.assertEqual(changelog.category(pr(1, "a", "ci/apk-przy-pushu-na-main")), "Zmienione")
        self.assertEqual(changelog.category(pr(1, "a", "dependabot/github_actions/x")), "Zmienione")
        self.assertEqual(changelog.category(pr(1, "a", "claude/serene-edison-5gql30")), "Zmienione")

    def test_labels_win_and_skip(self) -> None:
        self.assertEqual(changelog.category(pr(1, "a", "feat/x", labels=["Usuniete"])), "Usunięte")
        self.assertIsNone(changelog.category(pr(1, "a", "feat/x", labels=["bez-changelogu"])))

    def test_release_prs_are_skipped(self) -> None:
        self.assertIsNone(changelog.category(pr(1, "Wydanie 0.1.0", "chore/wydanie-0.1.0")))


class RenderTest(unittest.TestCase):
    def test_group_orders_by_merge_time_and_renders_sections(self) -> None:
        prs = [
            pr(12, "Druga  funkcja", "feat/b", "2026-11-14T00:00:00Z"),
            pr(11, "Pierwsza funkcja", "feat/a", "2026-11-13T00:00:00Z"),
            pr(13, "Poprawka", "fix/c"),
        ]
        text = changelog.render(changelog.group(prs))
        self.assertEqual(text, "### Dodane\n\n- Pierwsza funkcja (#11)\n- Druga funkcja (#12)\n\n"
                               "### Naprawione\n\n- Poprawka (#13)")

    def test_merge_keeps_manual_entries_first_without_duplicates(self) -> None:
        manual = changelog.parse_body("### Dodane\n\n- Ręczny wpis\n\n### Inne\n\n- Coś")
        gen = changelog.group([pr(5, "Z PR", "feat/x")])
        out = changelog.merge(manual, gen)
        self.assertEqual(out["Dodane"], ["Ręczny wpis", "Z PR (#5)"])
        self.assertEqual(changelog.merge(out, gen)["Dodane"], ["Ręczny wpis", "Z PR (#5)"])
        self.assertIn("### Inne\n\n- Coś", changelog.render(out))

    def test_empty_renders_nothing(self) -> None:
        self.assertEqual(changelog.render(changelog.group([])), "")


class MergedPrsTest(unittest.TestCase):
    def test_filters_by_merge_date_and_stops_paging(self) -> None:
        pages = {
            1: [
                {**pr(3, "nowy", "feat/a", "2026-11-14T00:00:00Z"), "updated_at": "2026-11-14T00:00:00Z"},
                {**pr(2, "zamknięty bez merge", "feat/b", None), "updated_at": "2026-11-13T12:00:00Z"},
                {**pr(1, "stary", "feat/c", "2026-11-01T00:00:00Z"), "updated_at": "2026-11-01T00:00:00Z"},
            ],
        }
        calls: list[str] = []

        def fake_get(path: str) -> list[dict]:
            calls.append(path)
            return pages.get(int(path.rsplit("=", 1)[1]), [])

        with mock.patch.object(changelog, "_get", fake_get):
            got = changelog.merged_prs("o/r", "2026-11-13T00:00:00Z")
        self.assertEqual([p["number"] for p in got], [3])
        self.assertEqual(len(calls), 1, "po starszym updated_at nie pobiera kolejnej strony")


class BumpTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        root = Path(__file__).resolve().parent.parent
        for name in ("project.godot", "export_presets.cfg"):
            shutil.copy(root / name, self.dir / name)
        (self.dir / "CHANGELOG.md").write_text(
            "# Changelog\n\n## [Nieopublikowane]\n\n## [0.0.1] - 2026-11-13\n\n### Dodane\n\n- Start\n",
            encoding="utf-8")
        self._set_version("0.0.1", 1)
        patches = [
            mock.patch.object(version, "PROJECT", self.dir / "project.godot"),
            mock.patch.object(version, "PRESETS", self.dir / "export_presets.cfg"),
            mock.patch.object(version, "CHANGELOG", self.dir / "CHANGELOG.md"),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(shutil.rmtree, self.dir)

    def _set_version(self, ver: str, code: int) -> None:
        proj = self.dir / "project.godot"
        proj.write_text(version.RE_PROJECT.sub(f'config/version="{ver}"', proj.read_text(encoding="utf-8")),
                        encoding="utf-8")
        pre = self.dir / "export_presets.cfg"
        text = version.RE_NAME.sub(f'version/name="{ver}"', pre.read_text(encoding="utf-8"))
        pre.write_text(version.RE_CODE.sub(f"version/code={code}", text), encoding="utf-8")

    def test_bump_writes_generated_section(self) -> None:
        gen = changelog.group([pr(80, "Budynki epoki I", "feat/etap-3"), pr(81, "Poprawka kamery", "fix/kamera")])
        with mock.patch.object(changelog, "generated_section", return_value=gen), \
                mock.patch("sys.stdout"):
            version.cmd_bump("minor")
        log = (self.dir / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("## [Nieopublikowane]\n\n## [0.1.0] - ", log)
        self.assertIn("### Dodane\n\n- Budynki epoki I (#80)\n\n### Naprawione\n\n- Poprawka kamery (#81)", log)
        self.assertEqual(version.current(), "0.1.0")
        with mock.patch("sys.stdout"):
            version.cmd_check(None)

    def test_bump_without_changes_fails(self) -> None:
        with mock.patch.object(changelog, "generated_section", return_value=changelog.group([])), \
                mock.patch("sys.stderr"), self.assertRaises(SystemExit):
            version.cmd_bump("patch")
        self.assertEqual(version.current(), "0.0.1")


if __name__ == "__main__":
    unittest.main()
