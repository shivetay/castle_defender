#!/usr/bin/env python3
"""Wersja gry i changelog w jednym miejscu.

Wersja (SemVer, MAJOR.MINOR.PATCH) żyje w trzech miejscach, które ten skrypt trzyma w zgodzie:
  project.godot       config/version="X.Y.Z"
  export_presets.cfg  version/name="X.Y.Z" i version/code=N (N = MAJOR*10000 + MINOR*100 + PATCH)
  CHANGELOG.md        sekcja "## [X.Y.Z] - RRRR-MM-DD"

Użycie:
  python3 tools/version.py current             wypisuje bieżącą wersję
  python3 tools/version.py check [--tag vX.Y.Z]  sprawdza zgodność (CI); z --tag także tag gita
  python3 tools/version.py bump patch|minor|major|X.Y.Z
                                               przenosi "Nieopublikowane" do nowej sekcji i podbija wersję
  python3 tools/version.py notes [X.Y.Z]       wypisuje opis wersji z changelogu (do GitHub Release)
"""
from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.godot"
PRESETS = ROOT / "export_presets.cfg"
CHANGELOG = ROOT / "CHANGELOG.md"

UNRELEASED = "Nieopublikowane"
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
RE_PROJECT = re.compile(r'^config/version="([^"]*)"$', re.M)
RE_NAME = re.compile(r'^version/name="([^"]*)"$', re.M)
RE_CODE = re.compile(r"^version/code=(\d+)$", re.M)
RE_SECTION = re.compile(r"^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$", re.M)


def fail(msg: str) -> None:
    print(f"BŁĄD: {msg}", file=sys.stderr)
    sys.exit(1)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def parse(version: str) -> tuple[int, int, int]:
    m = SEMVER.match(version)
    if not m:
        fail(f"'{version}' to nie jest wersja MAJOR.MINOR.PATCH")
    major, minor, patch = (int(g) for g in m.groups())
    if minor > 99 or patch > 99:
        fail(f"'{version}': MINOR i PATCH muszą być < 100 (inaczej version/code się zderzy)")
    return major, minor, patch


def version_code(version: str) -> int:
    major, minor, patch = parse(version)
    return major * 10000 + minor * 100 + patch


def find_one(regex: re.Pattern[str], text: str, where: str) -> str:
    found = regex.findall(text)
    if len(found) != 1:
        fail(f"{where}: oczekiwano dokładnie jednego wpisu {regex.pattern}, jest {len(found)}")
    return found[0]


def current() -> str:
    return find_one(RE_PROJECT, read(PROJECT), "project.godot")


def sections(text: str) -> list[tuple[str, str | None, int, int]]:
    """(nazwa, data, początek treści, koniec treści) dla każdej sekcji ## [..]."""
    marks = list(RE_SECTION.finditer(text))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        # treść sekcji kończy się przed odnośnikami [x]: url na końcu pliku, jeśli są
        out.append((m.group(1), m.group(2), m.end(), end))
    return out


def section_body(text: str, name: str) -> str | None:
    for sec, _date, start, end in sections(text):
        if sec == name:
            return text[start:end].strip()
    return None


def cmd_check(tag: str | None) -> None:
    ver = current()
    parse(ver)
    presets = read(PRESETS)
    name = find_one(RE_NAME, presets, "export_presets.cfg")
    code = int(find_one(RE_CODE, presets, "export_presets.cfg"))
    errors = []
    if name != ver:
        errors.append(f"export_presets.cfg version/name={name}, a project.godot ma {ver}")
    if code != version_code(ver):
        errors.append(f"export_presets.cfg version/code={code}, dla {ver} powinno być {version_code(ver)}")
    log = read(CHANGELOG)
    names = [s[0] for s in sections(log)]
    if not names or names[0] != UNRELEASED:
        errors.append(f"CHANGELOG.md: pierwsza sekcja musi być ## [{UNRELEASED}]")
    released = [(s[0], s[1]) for s in sections(log) if s[0] != UNRELEASED]
    if not released or released[0][0] != ver:
        top = released[0][0] if released else "brak"
        errors.append(f"CHANGELOG.md: najnowsza wydana sekcja to {top}, a wersja to {ver}")
    for sec, date in released:
        parse(sec)
        if date is None:
            errors.append(f"CHANGELOG.md: sekcja [{sec}] nie ma daty (## [{sec}] - RRRR-MM-DD)")
    if tag is not None and tag != f"v{ver}":
        errors.append(f"tag {tag} nie pasuje do wersji {ver} (oczekiwano v{ver})")
    if errors:
        for e in errors:
            print(f"BŁĄD: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: wersja {ver} (version/code {code}) zgodna w project.godot, export_presets.cfg i CHANGELOG.md")


def cmd_bump(what: str) -> None:
    old = current()
    major, minor, patch = parse(old)
    if what == "major":
        new = f"{major + 1}.0.0"
    elif what == "minor":
        new = f"{major}.{minor + 1}.0"
    elif what == "patch":
        new = f"{major}.{minor}.{patch + 1}"
    else:
        new = what
    if version_code(new) <= version_code(old):
        fail(f"nowa wersja {new} musi być wyższa niż {old}")

    log = read(CHANGELOG)
    body = section_body(log, UNRELEASED)
    if body is None:
        fail(f"CHANGELOG.md nie ma sekcji ## [{UNRELEASED}]")
    if not re.search(r"^\s*[-*] ", body, re.M):
        fail(f"sekcja [{UNRELEASED}] jest pusta: najpierw opisz zmiany")
    today = datetime.date.today().isoformat()
    header = f"## [{UNRELEASED}]"
    log = log.replace(header, f"{header}\n\n## [{new}] - {today}", 1)
    write(CHANGELOG, log)

    write(PROJECT, RE_PROJECT.sub(f'config/version="{new}"', read(PROJECT), count=1))
    presets = RE_NAME.sub(f'version/name="{new}"', read(PRESETS), count=1)
    presets = RE_CODE.sub(f"version/code={version_code(new)}", presets, count=1)
    write(PRESETS, presets)
    print(f"{old} -> {new} (version/code {version_code(new)}). Dalej:")
    print(f'  git commit -am "Wydanie {new}" && git tag v{new} && git push --follow-tags')


def cmd_notes(ver: str | None) -> None:
    ver = ver or current()
    body = section_body(read(CHANGELOG), ver)
    if body is None:
        fail(f"CHANGELOG.md nie ma sekcji [{ver}]")
    print(body)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("current")
    c = sub.add_parser("check")
    c.add_argument("--tag")
    b = sub.add_parser("bump")
    b.add_argument("what")
    n = sub.add_parser("notes")
    n.add_argument("version", nargs="?")
    a = p.parse_args()
    if a.cmd == "current":
        print(current())
    elif a.cmd == "check":
        cmd_check(a.tag)
    elif a.cmd == "bump":
        cmd_bump(a.what)
    else:
        cmd_notes(a.version)


if __name__ == "__main__":
    main()
