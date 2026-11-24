#!/bin/sh
# Entrypoint for the Godot verifier image (#284 / #301).
# Modes:
#   smoke          — print Godot version and exit 0 (default; no DB / no secrets)
#   godot [args…]  — run godot --headless with extra args
#   verify-pack    — require PACKS_DIR/verify_<SIM_VERSION>.pck and run a pack smoke
#   worker [args…] — Python claim/submit loop (needs VERIFIER_DATABASE_URL)
set -eu

mode="${1:-smoke}"
if [ "$#" -gt 0 ]; then
	shift
fi

case "$mode" in
	smoke)
		echo "castle-defender-verifier: Godot $(godot --headless --version 2>/dev/null || true)"
		echo "packs dir: ${PACKS_DIR:-/app/packs}"
		python3 -c "import psycopg; print('psycopg', psycopg.__version__)" 2>/dev/null \
			|| echo "psycopg: (not importable)"
		ls -la "${PACKS_DIR:-/app/packs}" 2>/dev/null || true
		exit 0
		;;
	godot)
		exec godot --headless "$@"
		;;
	verify-pack)
		sim="${SIM_VERSION:?SIM_VERSION required, e.g. 501 for 0.5.1}"
		pack="${PACKS_DIR:-/app/packs}/verify_${sim}.pck"
		if [ ! -f "$pack" ]; then
			echo "missing pack: $pack" >&2
			echo "mount or copy verify_*.pck into ${PACKS_DIR:-/app/packs}" >&2
			echo "TODO(#301): export preset Verifier + CI pack build — see packs/README.md" >&2
			exit 2
		fi
		# Pack-only smoke: load main pack; full --job/--out path needs verify_main.gd.
		exec godot --headless --main-pack "$pack" --quit-after 1
		;;
	worker)
		exec python3 /app/worker.py "$@"
		;;
	*)
		echo "usage: entrypoint.sh smoke|godot|verify-pack|worker [args…]" >&2
		exit 64
		;;
esac
