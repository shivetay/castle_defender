# Serwer

Praktyczny opis backendu Castle Defender / Dunhold: środowiska Supabase, migracje, Edge Functions,
worker weryfikacji na VPS i kolejność wdrożenia. Szczegóły checklisty po tagu: `docs/PO-WYDANIU.md`
w repo. Rozdział środowisk: notatka właścicielki o staging/prod (store Project).

Stan na: 27.11.2026 (Europe/Warsaw).

Powiązane: [[Backend PvP]], [[Stack technologiczny]], [[Model wydania]], [[ADR/README|ADR]]
(szczególnie [[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|0006]],
[[ADR/0008-wersja-symulacji-ataku-z-klienta|0008]],
[[ADR/0009-model-balansu-epok-ciagla-krzywa|0009]])

---

## 1. Środowiska

| Środowisko | Projekt Supabase | Kto łączy | Migracje |
| --- | --- | --- | --- |
| **local** | Docker (`supabase start`) | testy pgTAP, CI lokalne | zawsze |
| **staging** | obecny `castle_defender`, ref `wabeqpqrllwolhsceycd` (SoT; docelowo nazwa `…_staging`) | telefon / debug APK | swobodnie po merge, za zgodą właścicielki |
| **prod** | **jeszcze nie istnieje** — nowy projekt przy starcie testerów w Play | AAB / Play | tylko przy wydaniu, po smoke na staging |

**Rekomendacja:** obecna baza zostaje stagingiem; produkcji nie promujemy z danych testowych.
Wzorzec w org. Supabase: `guildBazaar_dev` / `guildBazaar_prod`.

Na jednym projekcie nie da się jednocześnie „swobodnie migrować” i „trzymać prawdziwych graczy”.

---

## 2. Klient i sekrety

- Klient Godot czyta `config/supabase.json` (`url` + `publishable_key`); plik poza gitem
  (`config/supabase.example.json` w repo).
- W kliencie **tylko** klucz publishable (`sb_publishable_…`). Nigdy `service_role` / `sb_secret_…`.
- CI (debug APK / AAB) zapisuje ten plik ze zmiennych: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`.
- Docelowo: debug APK → staging; AAB → osobne zmienne / Environment `production`. Dopóki nie ma
  splitu, wszystkie APK z Actions wskazują to, co stoi w `vars` — trzymaj tam staging.
- Auth: anonimowe na start; Google później — **per projekt** Supabase.

---

## 3. Migracje i Edge Functions

| Ścieżka w repo | Rola |
| --- | --- |
| `supabase/migrations/` | SQL: schemat, RLS, granty, RPC `private.*` |
| `supabase/functions/` | Edge Functions (`launch_attack`, `finish_attack`, `defense_history`, …) |
| `supabase/tests/database/` | pgTAP (RLS i sanity); CI job „Testy bazy” |

Rutyna po merge feature’a, który rusza backend (na **staging**):

1. Kod w repo — nie edytuj migracji już wgranej.
2. Opcjonalnie lokalnie: `supabase start` → `supabase test db`.
3. `supabase link --project-ref wabeqpqrllwolhsceycd`
4. Za zgodą właścicielki, z nazwą projektu: `supabase db push`
5. Potem EF: `supabase functions deploy … --project-ref …` (najpierw SQL, potem EF — EF może
   wołać nowe RPC). Przy zmianie `_shared` wgraj wszystkie funkcje.
6. Po wgraniu: Advisors (Security / Performance). RLS testuj w CI / lokalnie, nie „na żywo” na prod.

Zmiany na projekcie w chmurze **tylko za zgodą właścicielki**, za każdym razem, z nazwą / refem.

---

## 4. Verifier (VPS)

Worker Godot headless + Python (`server/verifier/`): odtwarza bitwę i woła
`private.claim_verification` / `private.submit_verification`.

| Element | Uwaga |
| --- | --- |
| `VERIFIER_DATABASE_URL` | pooler, user `verifier.<project-ref>` — osobny `.env` / compose dla staging i prod |
| Pack | `verify_$SIM.pck` z GitHub Release na dysku hosta |
| `private.sim_versions` | wiersz z `supported = true` **na tym samym** projekcie co worker |
| Tryb | `shadow` (porównanie) albo `enforce` (łup/ranking z wyniku workera) |
| `bot_verification_mode` | osobny klucz dla ataków na boty: `off` / `shadow` / `enforce`, domyślnie `shadow`; w `enforce` łup, PvE i `bots_beaten` idą z `verified_result` ([[ADR/0016-weryfikacja-atakow-na-zamki-boty\|ADR 0016]]) |
| Kolejka | najpierw ataki PvP, potem boty, FIFO w grupie; przed włączeniem `enforce` dla botów właścicielka podnosi `min_code` |
| Porzucone ataki | atak z zatwierdzonym planem porzucony w `shadow` / `enforce` idzie do kolejki, a wynik workera zamyka go jako `finished`; `claim_verification` sam porzuca ataki starsze niż 10 min ([[ADR/0018-porzucony-atak-rozstrzyga-serwer\|ADR 0018]]) |

Ryzyka: stagingowy worker piszący do prod; pack bez wiersza `sim_versions` → `unsupported_version`
/ ataki `failed`; wspólne hasło między projektami.

---

## 5. `sim_version` i progi klienta

- Atak PvP liczy się packiem wersji, którą klient podał przy zatwierdzeniu
  ([[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]]). Bez packa / bez wiersza w
  `sim_versions` — atak zablokowany.
- `public.client_versions`: `min_code` (blokada) i `recommended_code` (komunikat)
  ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]]).
- Zwykle: najpierw `recommended_code`, potem `min_code` po ~48 h. **Wyjątek** przy łamiącym
  bilansie (np. #384 / [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]): `min_code`
  od razu z wydaniem klienta — stary klient inaczej płaci za epokę II i dostaje
  `economy_too_fast` / `build_too_fast`.

---

## 6. Kolejność wdrożenia (skrót)

**Najpierw serwer, potem telefony.** Pełna lista: `docs/PO-WYDANIU.md`.

1. Tag / Release w GitHubie (CI zielone, pack `verify_$SIM.pck` w Release).
2. Staging: migracje + EF + smoke na debug APK.
3. Prod (gdy istnieje): te same migracje → EF → VPS pack + `sim_versions` + restart workera.
4. Dopiero potem AAB / Play z kluczem **prod**.
5. Progi `recommended_code` / `min_code` (z wyjątkiem z §5).

Pułapki z ostatnich PR-ów:

| Objaw | Przyczyna | Kolejność |
| --- | --- | --- |
| `unknown_field` z EF | nowy klient, stara allowlista EF | najpierw `functions deploy`, potem APK (#382) |
| `economy_too_fast` / `build_too_fast` | nowy bilans na serwerze, stary klient | migracja + klient razem; potem `min_code` (#384) |
| `unsupported_version` | brak `sim_versions` albo packa | insert + pack **przed** APK |
| Merge ≠ fix na serwerze | PR scalony, migracja/EF nie wgrane | osobny krok ops na właściwy project-ref |

---

## 7. Szybkie komendy

```bash
# Staging
export STAGING_REF=wabeqpqrllwolhsceycd
supabase link --project-ref "$STAGING_REF"
supabase db push
supabase functions deploy --project-ref "$STAGING_REF"
```

Lokalny klient: `config/supabase.json` → URL i publishable key ze staging.

Repo: `supabase/README.md`, `server/verifier/README.md`, `.github/scripts/supabase_config.sh`.
