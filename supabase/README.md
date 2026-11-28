# supabase/

Backend PvP: schemat Postgres, RLS, Edge Functions. Zmiany na projekcie w chmurze **tylko za zgodą**
właścicielki. Skill: `.claude/skills/supabase-security/`.

## Struktura

| Ścieżka | Rola |
|---|---|
| `config.toml` | Konfiguracja lokalnego stosu Supabase CLI |
| `migrations/` | Migracje SQL (schemat, RLS, granty) |
| `functions/` | Edge Functions (np. `start_attack/`) |
| `tests/database/` | Testy pgTAP: RLS (`rls_test.sql`), dobór, atak, ranking PvP (`ranking_test.sql`) i PvE (`pve_ranking_test.sql`), zwiad (`scouting_test.sql`), epoka z zamku (`castle_age_test.sql`), perk władcy (`ruler_perk_test.sql`), garnizon Dworu (`garrison_test.sql`), surowce i łup PvP na serwerze (`resource_sanity_test.sql`), zabudowa (`building_sanity_test.sql`), badania, wojsko i towary (`army_research_goods_sanity_test.sql`), bilans surowców (`economy_growth_test.sql`), fale PvE na serwerze (`pve_wave_test.sql`), weryfikacja ataków PvP przez worker (`attack_verification_test.sql`), kampania zamków-botów (`bot_campaign_test.sql`), weryfikacja ataków na zamki-boty (`bot_verification_test.sql`), porzucony atak rozstrzygany przez serwer (`abandoned_attack_test.sql`), straty armii na serwerze (`army_losses_test.sql`), tokeny push i jeden push na atak (`push_tokens_test.sql`) |
| `seed.sql` | Dane startowe lokalne |

## Lokalnie

```bash
supabase start
supabase test db
```

Bez Dockera i bez CLI Supabase (to samo robi job „Testy bazy (pgTAP)” w CI):

```bash
sudo apt-get install postgresql-16 postgresql-16-pgtap postgresql-16-cron libtap-parser-sourcehandler-pgtap-perl
bash .github/scripts/run_pgtap.sh
```

Skrypt stawia świeży, tymczasowy klaster (tylko gniazdo Unix), wgrywa zaślepkę platformy
(`.github/scripts/pgtap_supabase_stub.sql`), potem po kolei migracje i uruchamia `pg_prove`.
Nowa zależność od platformy (rola, schemat, funkcja `auth.*`) trafia do zaślepki.

Klient gry: `scripts/net/`. W kliencie tylko klucz publishable.
