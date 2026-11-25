#!/usr/bin/env bash
# Testy pgTAP bazy (supabase/tests/database) na świeżym, tymczasowym klastrze Postgres 16.
# Kolejność: initdb -> zaślepka Supabase (pgtap_supabase_stub.sql) -> migracje -> pg_prove.
# Klaster powstaje od zera przy każdym uruchomieniu i znika na końcu, więc role globalne
# (np. verifier z migracji) nie zostają z poprzednich przebiegów. Bez sieci i bez sekretów.
#
# Wymaga: postgresql-16, postgresql-16-pgtap, libtap-parser-sourcehandler-pgtap-perl (pg_prove).
# Lokalnie: bash .github/scripts/run_pgtap.sh (jako root uruchamia Postgresa przez użytkownika postgres).
set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
PG_PORT="${PG_PORT:-54329}"
export LC_COLLATE=C  # stała kolejność globów (migracje po znaczniku czasu)
LOG_DIR="${LOG_DIR:-build/logs}"
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd)"

# initdb i postgres odmawiają pracy jako root; wtedy używamy systemowego użytkownika postgres.
as_pg=()
if [ "$(id -u)" = "0" ]; then
	as_pg=(runuser -u postgres --)
fi

WORK="$(mktemp -d)"
chmod 755 "$WORK"
DATA="$WORK/data"
SOCK="$WORK/sock"
mkdir -p "$DATA" "$SOCK"
if [ "${#as_pg[@]}" -gt 0 ]; then
	chown -R postgres:postgres "$WORK"
fi
# Uwierzytelnianie trust tylko przez gniazdo w katalogu dostępnym wyłącznie dla właściciela klastra.
chmod 700 "$SOCK"

cleanup() {
	"${as_pg[@]}" "$PG_BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1 || true
	cp "$WORK/postgres.log" "$LOG_DIR/pgtap_postgres.log" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

echo "::group::Klaster Postgres 16"
"${as_pg[@]}" "$PG_BIN/initdb" -D "$DATA" -U postgres --auth=trust --encoding=UTF8 --locale=C.UTF-8 >/dev/null
# Tylko gniazdo Unix w katalogu tymczasowym: brak nasłuchu TCP.
"${as_pg[@]}" "$PG_BIN/pg_ctl" -D "$DATA" -l "$WORK/postgres.log" -w \
	-o "-c listen_addresses='' -k $SOCK -p $PG_PORT" start
"${as_pg[@]}" "$PG_BIN/postgres" --version
echo "::endgroup::"

export PGHOST="$SOCK" PGPORT="$PG_PORT" PGUSER=postgres PGDATABASE=postgres
export PGOPTIONS="-c client_min_messages=warning"
psql_run() {  # psql_run <plik.sql>
	"${as_pg[@]}" env PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGDATABASE="$PGDATABASE" PGOPTIONS="$PGOPTIONS" \
		psql -X -q -v ON_ERROR_STOP=1 -f "$1"
}

echo "::group::Zaślepka Supabase"
psql_run "$ROOT/.github/scripts/pgtap_supabase_stub.sql"
echo "::endgroup::"

echo "::group::Migracje"
shopt -s nullglob
migrations=("$ROOT"/supabase/migrations/*.sql)
tests=("$ROOT"/supabase/tests/database/*.sql)
if [ "${#migrations[@]}" -eq 0 ] || [ "${#tests[@]}" -eq 0 ]; then
	echo "Brak migracji albo testów w supabase/" >&2
	exit 1
fi
for f in "${migrations[@]}"; do  # glob sortuje po nazwie, czyli po znaczniku czasu
	echo "-> ${f#"$ROOT"/}"
	psql_run "$f"
done
echo "::endgroup::"

echo "::group::pg_prove"
"${as_pg[@]}" env PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGDATABASE="$PGDATABASE" PGOPTIONS="$PGOPTIONS" \
	pg_prove --ext .sql --failures "${tests[@]}" 2>&1 | tee "$LOG_DIR/pgtap.log"
status=${PIPESTATUS[0]}
echo "::endgroup::"
exit "$status"
