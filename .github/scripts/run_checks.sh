#!/usr/bin/env bash
# Pełna weryfikacja projektu: wersja, import, kompilacja, test dymny, testy logiki.
# Działa w CI i lokalnie (Linux, macOS, Git Bash na Windows): GODOT=ścieżka/do/godota bash .github/scripts/run_checks.sh
set -uo pipefail

GODOT="${GODOT:-godot}"
LOG_DIR="${LOG_DIR:-build/logs}"
cd "$(dirname "$0")/../.."
mkdir -p "$LOG_DIR"
status=0

step() {  # step <nazwa> <komenda...>
	local name="$1"
	shift
	echo "::group::$name"
	if "$@"; then
		echo "::endgroup::"
		echo "OK   $name"
	else
		echo "::endgroup::"
		echo "FAIL $name"
		status=1
	fi
}

smoke() {
	# Godot kończy się kodem 0 nawet po błędach skryptu, więc oceniamy log, nie kod wyjścia.
	timeout 120 "$GODOT" --headless --path . --quit-after 300 >"$LOG_DIR/smoke.log" 2>&1
	if grep -nE "SCRIPT ERROR|^ERROR:" "$LOG_DIR/smoke.log"; then
		return 1
	fi
	echo "log czysty ($LOG_DIR/smoke.log)"
}

step "Wersja i changelog" python3 tools/version.py check
step "Import projektu" timeout 300 "$GODOT" --headless --path . --import
step "Kompilacja skryptów" timeout 120 "$GODOT" --headless --path . --script res://tests/check_compile.gd
step "Test dymny (300 klatek)" smoke
step "Testy logiki" timeout 300 "$GODOT" --headless --path . --script res://tests/run_tests.gd

exit $status
