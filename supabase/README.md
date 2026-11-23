# supabase/

Backend PvP: schemat Postgres, RLS, Edge Functions. Zmiany na projekcie w chmurze **tylko za zgodą**
właścicielki. Skill: `.claude/skills/supabase-security/`.

## Struktura

| Ścieżka | Rola |
|---|---|
| `config.toml` | Konfiguracja lokalnego stosu Supabase CLI |
| `migrations/` | Migracje SQL (schemat, RLS, granty) |
| `functions/` | Edge Functions (np. `start_attack/`) |
| `tests/database/` | Testy pgTAP: RLS (`rls_test.sql`), dobór, atak, ranking PvP (`ranking_test.sql`) i PvE (`pve_ranking_test.sql`), zwiad (`scouting_test.sql`), epoka z zamku (`castle_age_test.sql`), perk władcy (`ruler_perk_test.sql`), garnizon Dworu (`garrison_test.sql`), surowce i łup PvP na serwerze (`resource_sanity_test.sql`) |
| `seed.sql` | Dane startowe lokalne |

## Lokalnie

```bash
supabase start
supabase test db
```

Klient gry: `scripts/net/`. W kliencie tylko klucz publishable.
