#!/usr/bin/env bash
# Buduje AAR wtyczki Androida DunholdPush (#30, ADR 0012) z tools/android/push_plugin i kopiuje go do
# addons/dunhold_push/bin/, skąd bierze go eksport (addons/dunhold_push/export_plugin.gd).
# Z sekretu GOOGLE_SERVICES_JSON (base64 pliku z konsoli Firebase) zapisuje config/google-services.json
# (w .gitignore, poza paczką gry). Bez sekretu AAR i tak powstaje, a gra działa bez pusha.
# Wymaga: JDK 17, Gradle 8.9+ i Android SDK ($ANDROID_HOME).
set -euo pipefail

cd "$(dirname "$0")/../.."

if [ -n "${GOOGLE_SERVICES_JSON:-}" ]; then
	umask 077
	echo "$GOOGLE_SERVICES_JSON" | base64 --decode > config/google-services.json
	python3 -c 'import json; json.load(open("config/google-services.json"))' \
		|| { echo "::error::GOOGLE_SERVICES_JSON to nie jest JSON w base64"; rm -f config/google-services.json; exit 1; }
	echo "Zapisano config/google-services.json"
else
	echo "Brak GOOGLE_SERVICES_JSON: eksport bez powiadomień push"
fi

(cd tools/android/push_plugin && gradle --no-daemon --console=plain assembleRelease)
mkdir -p addons/dunhold_push/bin
cp tools/android/push_plugin/build/outputs/aar/dunhold_push-release.aar addons/dunhold_push/bin/dunhold_push.aar
ls -la addons/dunhold_push/bin/
