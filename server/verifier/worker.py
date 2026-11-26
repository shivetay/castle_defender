#!/usr/bin/env python3
# Claim/submit loop for the PvP verification worker (#284 / #301).
# Talks only to private.claim_verification / private.submit_verification.
# Never logs connection strings, job payloads, or player data.
from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse, urlunparse

import psycopg

GODOT_TIMEOUT_S = 120
IDLE_SLEEP_S = 2.0
LOG = logging.getLogger("verifier")


def _env_path(name: str, default: str) -> Path:
	return Path(os.environ.get(name, default))


def redact_database_url(url: str) -> str:
	"""Strip userinfo from a DB URL for safe error messages."""
	if not url:
		return "<empty>"
	parsed = urlparse(url)
	if parsed.username is None and parsed.password is None:
		return url
	host = parsed.hostname or ""
	if parsed.port:
		host = f"{host}:{parsed.port}"
	netloc = host
	return urlunparse(
		(parsed.scheme, netloc, parsed.path, parsed.params, parsed.query, parsed.fragment)
	)


def claim_job(conn: psycopg.Connection[Any], worker_id: str) -> dict[str, Any] | None:
	"""Call private.claim_verification; returns one job dict or None if queue empty."""
	with conn.cursor() as cur:
		cur.execute("SELECT private.claim_verification(%s)", (worker_id,))
		row = cur.fetchone()
	if row is None or row[0] is None:
		return None
	payload: Any = row[0]
	if isinstance(payload, memoryview):
		payload = bytes(payload)
	if isinstance(payload, (bytes, bytearray)):
		payload = payload.decode("utf-8")
	if isinstance(payload, str):
		parsed: Any = json.loads(payload)
	else:
		parsed = payload
	if not isinstance(parsed, dict):
		raise TypeError(f"claim_verification returned {type(parsed).__name__}, expected object")
	return parsed


def submit_result(
	conn: psycopg.Connection[Any], attack_id: str, result: dict[str, Any]
) -> None:
	"""Call private.submit_verification with the Godot worker result."""
	with conn.cursor() as cur:
		cur.execute(
			"SELECT private.submit_verification(%s::uuid, %s::jsonb)",
			(attack_id, json.dumps(result, separators=(",", ":"))),
		)


def pack_path_for(sim_version: int, packs_dir: Path) -> Path:
	return packs_dir / f"verify_{sim_version}.pck"


def run_godot_job(
	job: dict[str, Any],
	*,
	packs_dir: Path,
	tmpdir: Path,
	godot_bin: str,
	timeout_s: int = GODOT_TIMEOUT_S,
) -> dict[str, Any]:
	"""Write job JSON, run headless pack, read result JSON."""
	if "sim_version" not in job:
		raise KeyError("job missing sim_version")
	sim_version = int(job["sim_version"])
	pack = pack_path_for(sim_version, packs_dir)
	if not pack.is_file():
		raise FileNotFoundError(f"missing pack verify_{sim_version}.pck")

	tmpdir.mkdir(parents=True, exist_ok=True)
	with tempfile.TemporaryDirectory(dir=tmpdir) as td:
		td_path = Path(td)
		job_path = td_path / "job.json"
		out_path = td_path / "out.json"
		job_path.write_text(json.dumps(job, separators=(",", ":")), encoding="utf-8")
		cmd = [
			godot_bin,
			"--headless",
			"--main-pack",
			str(pack),
			"--",
			"--job",
			str(job_path),
			"--out",
			str(out_path),
		]
		# Pack z presetu „Verifier” (#305) startuje VerifyMain sam, bez --script (#303).
		proc = subprocess.run(
			cmd,
			capture_output=True,
			text=True,
			timeout=timeout_s,
			check=False,
		)
		if proc.returncode != 0:
			stderr_tail = (proc.stderr or "").strip()[-200:]
			raise RuntimeError(
				f"godot exit {proc.returncode}"
				+ (f": {stderr_tail}" if stderr_tail else "")
			)
		if not out_path.is_file():
			raise RuntimeError("godot finished without out.json")
		raw = out_path.read_text(encoding="utf-8")
		parsed: Any = json.loads(raw)
		if not isinstance(parsed, dict):
			raise TypeError("out.json must be a JSON object")
		return parsed


def attack_id_of(job: dict[str, Any]) -> str:
	for key in ("attack_id", "id"):
		value = job.get(key)
		if value is not None:
			return str(value)
	raise KeyError("job missing attack_id")


def process_one(
	conn: psycopg.Connection[Any],
	*,
	worker_id: str,
	packs_dir: Path,
	tmpdir: Path,
	godot_bin: str,
) -> bool:
	"""Claim one job and submit. Returns False if queue was empty."""
	job = claim_job(conn, worker_id)
	if job is None:
		conn.rollback()
		return False
	# Publish lease before the long Godot run (do not hold an open txn across CPU work).
	conn.commit()
	attack_id = attack_id_of(job)
	t0 = time.monotonic()
	try:
		result = run_godot_job(
			job, packs_dir=packs_dir, tmpdir=tmpdir, godot_bin=godot_bin
		)
		submit_result(conn, attack_id, result)
		conn.commit()
		elapsed_ms = int((time.monotonic() - t0) * 1000)
		LOG.info("ok attack_id=%s elapsed_ms=%s", attack_id, elapsed_ms)
	except Exception as exc:
		# Leave lease; SQL attempts/last_error path is owned by claim/submit (#284 §3).
		conn.rollback()
		elapsed_ms = int((time.monotonic() - t0) * 1000)
		LOG.error(
			"fail attack_id=%s elapsed_ms=%s err=%s",
			attack_id,
			elapsed_ms,
			type(exc).__name__,
		)
	return True


# prepare_threshold=None: no server-side prepared statements. The Supabase pooler in
# transaction mode (port 6543) can hand the next query to another backend, where a
# statement prepared by psycopg after a few idle claims does not exist.
CONNECT_KWARGS: dict[str, Any] = {"autocommit": False, "prepare_threshold": None}


def connect(database_url: str) -> psycopg.Connection[Any]:
	return psycopg.connect(database_url, **CONNECT_KWARGS)


def run_loop(
	*,
	database_url: str,
	worker_id: str,
	packs_dir: Path,
	tmpdir: Path,
	godot_bin: str,
	once: bool,
	idle_sleep_s: float = IDLE_SLEEP_S,
) -> int:
	try:
		conn = connect(database_url)
	except Exception as exc:
		LOG.error(
			"db connect failed host=%s err=%s",
			redact_database_url(database_url),
			type(exc).__name__,
		)
		return 2

	LOG.info("worker start id=%s packs=%s", worker_id, packs_dir)
	try:
		while True:
			had_job = process_one(
				conn,
				worker_id=worker_id,
				packs_dir=packs_dir,
				tmpdir=tmpdir,
				godot_bin=godot_bin,
			)
			if once:
				return 0 if had_job else 1
			if not had_job:
				time.sleep(idle_sleep_s)
	finally:
		conn.close()


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="PvP verification claim/submit worker")
	parser.add_argument(
		"--once",
		action="store_true",
		help="Process at most one job then exit (1 if queue empty)",
	)
	parser.add_argument(
		"--godot",
		default=os.environ.get("GODOT_BIN", "godot"),
		help="Godot binary (default: godot or GODOT_BIN)",
	)
	args = parser.parse_args(argv)

	logging.basicConfig(
		level=logging.INFO,
		format="%(asctime)s %(levelname)s %(message)s",
		datefmt="%Y-%m-%dT%H:%M:%SZ",
	)

	database_url = os.environ.get("VERIFIER_DATABASE_URL", "").strip()
	if not database_url:
		LOG.error("VERIFIER_DATABASE_URL is required for worker mode")
		return 2

	worker_id = os.environ.get("WORKER_ID", "").strip() or "worker-1"
	packs_dir = _env_path("PACKS_DIR", "/app/packs")
	tmpdir = _env_path("TMPDIR", "/tmp/verifier")

	return run_loop(
		database_url=database_url,
		worker_id=worker_id,
		packs_dir=packs_dir,
		tmpdir=tmpdir,
		godot_bin=args.godot,
		once=args.once,
	)


if __name__ == "__main__":
	sys.exit(main())
