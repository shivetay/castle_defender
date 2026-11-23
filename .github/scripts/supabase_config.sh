#!/usr/bin/env bash
# Zapisuje config/supabase.json ze zmiennych repozytorium SUPABASE_URL i SUPABASE_PUBLISHABLE_KEY.
# Klucz publishable jest publiczny z założenia (trafia do APK/AAB); klucza serwera tu nie ma.
set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
	echo "Brak zmiennych SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY: gra działa offline"
	exit 0
fi
case "$SUPABASE_PUBLISHABLE_KEY" in
	sb_publishable_*) ;;
	*) echo "::error::SUPABASE_PUBLISHABLE_KEY musi zaczynać się od sb_publishable_"; exit 1 ;;
esac
case "$SUPABASE_URL" in
	https://*) ;;
	*) echo "::error::SUPABASE_URL musi zaczynać się od https://"; exit 1 ;;
esac
python3 -c 'import json, os; json.dump({"url": os.environ["SUPABASE_URL"], "publishable_key": os.environ["SUPABASE_PUBLISHABLE_KEY"]}, open("config/supabase.json", "w"))'
echo "Zapisano config/supabase.json"
