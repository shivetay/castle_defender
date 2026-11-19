# .github/

CI/CD i szablony PR.

## Kluczowe pliki

| Ścieżka | Rola |
|---|---|
| `workflows/ci.yml` | Push/PR: wersja, import, kompilacja, smoke, testy logiki |
| `workflows/release.yml` | APK / GitHub Release przy `main` i tagach `v*` |
| `workflows/prepare-release.yml` | Ręczne przygotowanie PR-a wydania |
| `scripts/run_checks.sh` | Lokalny odpowiednik CI |
| `scripts/install_godot.sh` | Pobranie Godota 4.7.2 + weryfikacja SHA-512 |
| `pull_request_template.md` | Szablon opisu PR (w tym sekcja Bezpieczeństwo) |

Przed zgłoszeniem „gotowe”: `bash .github/scripts/run_checks.sh`.
