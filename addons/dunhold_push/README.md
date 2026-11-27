# addons/dunhold_push/

Wtyczka edytora dla powiadomień push na Androidzie (#30, ADR 0012). Włączona w `project.godot`
(`[editor_plugins]`), działa tylko przy eksporcie Androida z Gradle.

| Plik | Rola |
|---|---|
| `plugin.gd` | Rejestruje eksport |
| `export_plugin.gd` | Dokłada AAR `bin/dunhold_push.aar`, Firebase Messaging i wpisy `meta-data` z konfiguracją Firebase |
| `firebase_config.gd` | `FirebaseConfig`: wybiera z `config/google-services.json` aplikację o pakiecie presetu |
| `bin/` | AAR z `bash .github/scripts/build_push_plugin.sh` (w `.gitignore`) |

Bez AAR albo bez `config/google-services.json` eksport idzie dalej, a gra działa bez pusha.
Źródło wtyczki Androida: `tools/android/push_plugin/`.
