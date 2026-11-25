#!/usr/bin/env python3
# Lightweight unit checks for worker helpers (no DB, no Godot).
from __future__ import annotations

import sys
from pathlib import Path

# Allow `python test_worker_unit.py` from this directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from worker import attack_id_of, pack_path_for, redact_database_url  # noqa: E402


def test_redact_database_url() -> None:
	raw = "postgresql://verifier:s3cret@db.example.com:6543/postgres"
	redacted = redact_database_url(raw)
	assert "s3cret" not in redacted
	assert "verifier:" not in redacted
	assert "db.example.com:6543" in redacted
	assert redact_database_url("") == "<empty>"


def test_attack_id_of() -> None:
	assert attack_id_of({"attack_id": "a1"}) == "a1"
	assert attack_id_of({"id": "b2"}) == "b2"
	try:
		attack_id_of({})
		raise AssertionError("expected KeyError")
	except KeyError:
		pass


def test_pack_path_for() -> None:
	path = pack_path_for(501, Path("/app/packs"))
	assert path.as_posix() == "/app/packs/verify_501.pck"


def main() -> int:
	test_redact_database_url()
	test_attack_id_of()
	test_pack_path_for()
	print("test_worker_unit: ok")
	return 0


if __name__ == "__main__":
	sys.exit(main())
