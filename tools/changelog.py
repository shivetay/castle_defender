#!/usr/bin/env python3
"""Changelog generowany ze scalonych PR-ów.

Każdy PR scalony do main od ostatniego tagu v* staje się jednym wpisem: "Tytuł PR (#N)".
Podsekcję wybiera (w tej kolejności):
  1. etykieta PR: dodane, zmienione, naprawione, usuniete; etykieta bez-changelogu pomija PR,
  2. prefiks gałęzi z CLAUDE.md: feat/ -> Dodane, fix/ -> Naprawione,
     ci/ docs/ chore/ refactor/ test/ dependabot/ -> Zmienione,
  3. w pozostałych przypadkach: Zmienione.
PR-y wydań (gałąź chore/wydanie-*) są pomijane.

Dane pobiera z GitHub REST API: token z GITHUB_TOKEN albo GH_TOKEN, a bez nich przez `gh api`.

Użycie:
  python3 tools/changelog.py preview [--repo owner/name]   wypisuje sekcję dla następnego wydania
Wydanie (`tools/version.py bump`) wywołuje to samo i wpisuje wynik do CHANGELOG.md.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

HEADINGS = ["Dodane", "Zmienione", "Naprawione", "Usunięte"]
LABELS = {"dodane": "Dodane", "zmienione": "Zmienione", "naprawione": "Naprawione", "usuniete": "Usunięte"}
SKIP_LABEL = "bez-changelogu"
BRANCH_PREFIX = {
    "feat": "Dodane",
    "fix": "Naprawione",
    "ci": "Zmienione",
    "docs": "Zmienione",
    "chore": "Zmienione",
    "refactor": "Zmienione",
    "test": "Zmienione",
    "dependabot": "Zmienione",
}
RELEASE_BRANCH = re.compile(r"^chore/wydanie-")


def category(pr: dict) -> str | None:
    """Podsekcja changelogu dla PR albo None, gdy PR ma nie trafić do changelogu."""
    labels = [str(lab.get("name", "")).lower() for lab in pr.get("labels", [])]
    if SKIP_LABEL in labels:
        return None
    branch = str(pr.get("head", {}).get("ref", ""))
    if RELEASE_BRANCH.match(branch):
        return None
    for lab in labels:
        if lab in LABELS:
            return LABELS[lab]
    return BRANCH_PREFIX.get(branch.split("/", 1)[0], "Zmienione")


def entry(pr: dict) -> str:
    title = " ".join(str(pr["title"]).split())
    return f"{title} (#{pr['number']})"


def group(prs: list[dict]) -> dict[str, list[str]]:
    """Wpisy pogrupowane w podsekcje, w kolejności scalania."""
    out: dict[str, list[str]] = {h: [] for h in HEADINGS}
    for pr in sorted(prs, key=lambda p: str(p.get("merged_at") or "")):
        cat = category(pr)
        if cat is not None:
            out[cat].append(entry(pr))
    return out


def parse_body(body: str) -> dict[str, list[str]]:
    """Ręczne wpisy z sekcji changelogu (### Podsekcja / - wpis)."""
    out: dict[str, list[str]] = {h: [] for h in HEADINGS}
    current = "Zmienione"
    for line in body.splitlines():
        m = re.match(r"^###\s+(.+?)\s*$", line)
        if m:
            current = m.group(1)
            out.setdefault(current, [])
            continue
        m = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
        if m:
            out.setdefault(current, []).append(m.group(1))
    return out


def render(groups: dict[str, list[str]]) -> str:
    """Treść sekcji: niepuste podsekcje w kolejności HEADINGS, potem ewentualne inne."""
    order = HEADINGS + [h for h in groups if h not in HEADINGS]
    parts = []
    for h in order:
        items = groups.get(h, [])
        if items:
            parts.append(f"### {h}\n\n" + "\n".join(f"- {i}" for i in items))
    return "\n\n".join(parts)


def merge(manual: dict[str, list[str]], generated: dict[str, list[str]]) -> dict[str, list[str]]:
    out = {h: list(v) for h, v in manual.items()}
    for h, items in generated.items():
        out.setdefault(h, [])
        out[h].extend(i for i in items if i not in out[h])
    return out


def last_tag_date() -> str | None:
    """Data (ISO 8601) commita ostatniego tagu v* albo None przed pierwszym tagiem."""
    try:
        tag = subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", "v*"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout.strip()
    except subprocess.CalledProcessError:
        return None
    return subprocess.run(["git", "log", "-1", "--format=%cI", tag], cwd=ROOT,
                          capture_output=True, text=True, check=True).stdout.strip()


def default_repo() -> str:
    env = os.environ.get("GITHUB_REPOSITORY")
    if env:
        return env
    url = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.strip()
    m = re.search(r"([^/:]+/[^/]+?)(?:\.git)?$", url)
    if not m:
        raise SystemExit(f"BŁĄD: nie rozpoznaję repozytorium z {url}; podaj --repo owner/name")
    return m.group(1)


def _get(path: str) -> list[dict]:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req = urllib.request.Request(f"https://api.github.com/{path}", headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "castle-defender-changelog",
        })
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    try:
        out = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=True).stdout
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        raise SystemExit(f"BŁĄD: brak dostępu do GitHub API (ustaw GITHUB_TOKEN albo zaloguj gh): {e}")
    return json.loads(out)


def merged_prs(repo: str, since: str | None) -> list[dict]:
    """PR-y scalone do main po `since` (ISO 8601) albo wszystkie, gdy since to None."""
    prs: list[dict] = []
    page = 1
    while True:
        batch = _get(f"repos/{repo}/pulls?state=closed&base=main&sort=updated&direction=desc"
                     f"&per_page=100&page={page}")
        if not batch:
            break
        for pr in batch:
            merged = pr.get("merged_at")
            if merged and (since is None or merged > since):
                prs.append(pr)
        # lista jest malejąco po updated_at, a scalenie zawsze aktualizuje PR
        if since is not None and str(batch[-1].get("updated_at", "")) <= since:
            break
        page += 1
    return prs


def generated_section(repo: str | None = None) -> dict[str, list[str]]:
    since = last_tag_date()
    return group(merged_prs(repo or default_repo(), _utc(since)))


def _utc(iso: str | None) -> str | None:
    """Data z gita (z przesunięciem strefy) w formacie GitHuba: RRRR-MM-DDTHH:MM:SSZ."""
    if iso is None:
        return None
    from datetime import datetime, timezone
    return datetime.fromisoformat(iso).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    pv = sub.add_parser("preview")
    pv.add_argument("--repo")
    a = p.parse_args()
    if a.cmd == "preview":
        text = render(generated_section(a.repo))
        print(text or "(brak scalonych PR-ów od ostatniego tagu)")


if __name__ == "__main__":
    sys.exit(main())
