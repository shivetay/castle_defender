# .github/

CI/CD i szablony PR.

## Kluczowe pliki

| Ścieżka | Rola |
|---|---|
| `workflows/ci.yml` | Push/PR: wersja, import, kompilacja, smoke, testy logiki; osobny job z testami pgTAP bazy |
| `workflows/release.yml` | APK / GitHub Release przy `main` i tagach `v*` |
| `workflows/prepare-release.yml` | Ręczne przygotowanie PR-a wydania |
| `scripts/run_checks.sh` | Lokalny odpowiednik CI |
| `scripts/run_pgtap.sh` | Testy pgTAP: świeży klaster Postgres 16, zaślepka Supabase, migracje, `pg_prove` |
| `scripts/pgtap_supabase_stub.sql` | Zaślepka platformy Supabase (role API, `auth.users`, `auth.uid()`, granty) |
| `scripts/install_godot.sh` | Pobranie Godota 4.7.2 + weryfikacja SHA-512 |
| `pull_request_template.md` | Szablon opisu PR (w tym sekcja Bezpieczeństwo) |

Przed zgłoszeniem „gotowe”: `bash .github/scripts/run_checks.sh`, a przy zmianie w `supabase/` także
`bash .github/scripts/run_pgtap.sh`.
