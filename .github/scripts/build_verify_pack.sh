#!/usr/bin/env bash
# Buduje pack weryfikacji bitew dla workera (#284 / #305): preset „Verifier” → <katalog>/verify_<sim_version>.pck,
# gdzie sim_version = kod wersji gry (MAJOR*10000 + MINOR*100 + PATCH, jak version/code w tools/version.py).
# Eksport packa nie potrzebuje szablonów eksportu, wystarczy sam Godot z install_godot.sh.
#   bash .github/scripts/build_verify_pack.sh [katalog]           (domyślnie server/verifier/packs)
#   bash .github/scripts/build_verify_pack.sh --check [katalog]   (+ pack liczy fiksturę jak źródło)
# Wymaga wcześniejszego `godot --headless --path . --import`.
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../.."
root="$(pwd)"

check=0
if [[ "${1:-}" == "--check" ]]; then
	check=1
	shift
fi
out_dir="${1:-server/verifier/packs}"
mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd)"

version="$(python3 tools/version.py current)"
IFS=. read -r major minor patch <<<"$version"
sim_version=$((major * 10000 + minor * 100 + patch))
pack="$out_dir/verify_${sim_version}.pck"
log_dir="$root/${LOG_DIR:-build/logs}"
mkdir -p "$log_dir"

# Godot kończy się kodem 0 nawet po błędach skryptu, więc oceniamy też log.
no_errors() {  # no_errors <log>
	if grep -nE "SCRIPT ERROR|^ERROR:" "$1"; then
		echo "błędy w logu: $1"
		return 1
	fi
}

rm -f "$pack"
timeout 300 "$GODOT" --headless --path . --export-pack "Verifier" "$pack" >"$log_dir/verify_pack_export.log" 2>&1
no_errors "$log_dir/verify_pack_export.log"
test -s "$pack" || { echo "Brak packa po eksporcie: $pack"; exit 1; }
echo "pack: $pack ($(wc -c <"$pack") B, sim_version $sim_version)"

# Pack nie może zawierać konfiguracji klienta (adres i klucz Supabase) ani plików spoza symulacji.
# Katalog packa trzyma ścieżki plików jawnym tekstem (`config/…`), a skrypty są w nim tokenizowane.
if strings "$pack" | grep -qE '^(res://)?config/'; then
	echo "Pack zawiera pliki z config/: sprawdź include_filter i exclude_filter presetu Verifier"
	exit 1
fi

if [[ "$check" == 0 ]]; then
	exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 1) Pack startuje sam (bez --script) i poświadcza wersję z nazwy pliku.
timeout 60 "$GODOT" --headless --main-pack "$pack" -- --check >"$log_dir/verify_pack_check.log" 2>&1
no_errors "$log_dir/verify_pack_check.log"
grep -qx "sim_version=${sim_version}" "$log_dir/verify_pack_check.log" \
	|| { echo "Pack nie zgłasza sim_version=${sim_version}"; exit 1; }

# 2) Fikstura z testów: job i wynik VerifyJob policzony ze źródeł.
timeout 120 "$GODOT" --headless --path . --script res://tests/verify_pack_fixture.gd -- --dir "$work" \
	>"$log_dir/verify_pack_fixture.log" 2>&1
no_errors "$log_dir/verify_pack_fixture.log"

# 3) Ten sam job w packu, tak jak woła go worker.py.
timeout 120 "$GODOT" --headless --main-pack "$pack" -- --job "$work/job.json" --out "$work/out.json" \
	>"$log_dir/verify_pack_job.log" 2>&1
no_errors "$log_dir/verify_pack_job.log"
python3 - "$work/expected.json" "$work/out.json" <<'EOF'
import json
import sys

expected = json.load(open(sys.argv[1], encoding="utf-8"))
got = json.load(open(sys.argv[2], encoding="utf-8"))
if got != expected:
    print("Pack liczy inaczej niż źródło:")
    for key in sorted(set(expected) | set(got)):
        if expected.get(key) != got.get(key):
            print(f"  {key}: źródło={expected.get(key)!r} pack={got.get(key)!r}")
    sys.exit(1)
print(f"pack = źródło: checksum {got['checksum']}, {got['percent']}%, ticks {got['ticks']}")
EOF
