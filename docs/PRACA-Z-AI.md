# Praca z AI: który skill kiedy

Mapa przepływu pracy agentów (Claude Code, Cursor) w Castle Defender. Zasady są w `CLAUDE.md`,
skille w `.claude/skills/`. Tu jest tylko odpowiedź na pytanie „od czego zacząć”.

## Główna ścieżka: ticket → PR

1. **Ticket na GitHubie** → agent sam uruchamia `implement`, a ten zaczyna od `grilling`:
   czyta issue, komentarze, kod, vault i ADR-y, a potem zadaje pytania w rundach. Przy każdym pytaniu
   podaje rekomendację, a „tak” ją akceptuje. Zawsze jest co najmniej jedna runda, choćby z samymi
   założeniami do potwierdzenia. Kod powstaje dopiero po Twoim potwierdzeniu.
2. **Ustalenia** trafiają do komentarza w issue. Decyzje trudne do odwrócenia albo zmieniające
   projekt gry dostają ADR (`adr`) w `docs/castle-defender-vault/ADR/`, a skill aktualizuje
   dotknięte notatki vaultu.
3. **Kod test-first** (`tdd`) na uzgodnionych szwach testowych, potem `run_checks.sh`,
   review bezpieczeństwa (`security-review`) i PR, który agent obserwuje do merge'a.

## Większy pomysł: rozmowa → specyfikacja → tickety

1. `/grill-me`: wywiad o pomyśle, aż wszystkie decyzje będą ustalone (ADR-y po drodze).
2. `/to-spec`: specyfikacja jako issue na GitHubie (bez nowego wywiadu, tylko synteza).
3. `/to-tickets`: rozbicie na pionowe plasterki jako sub-issues z „Blokowane przez”.
   Pokazuje rozbicie do akceptacji, zanim cokolwiek opublikuje.
4. Każdy ticket osobno przez `implement`, najlepiej w świeżej sesji.

Kroki 1–3 rób w jednej sesji, żeby specyfikacja i tickety opierały się na tym samym rozumowaniu.

## Pozostałe

| Skill | Kiedy |
|---|---|
| `/handoff` | Przekazanie pracy innej sesji, innemu narzędziu albo człowiekowi |
| `writing-for-agents` | Zmiana skilli, `CLAUDE.md`, `AGENTS.md`, `.cursor/` albo tego pliku |
| `security-review`, `supabase-security`, `pvp-anti-cheat`, `user-data-privacy` | Bezpieczeństwo (`CLAUDE.md`) |
| skille Godota i gamedev | Wczytują się same przy pasującym zadaniu (tabela w `CLAUDE.md`) |

Skille z `/` na początku wywołujesz ręcznie (agent ich sam nie odpala). Pozostałe agent wczytuje
sam, gdy pasują do zadania.

## Źródła prawdy

- **Decyzja**: ADR. **Specyfikacja gry**: vault (idzie za ADR-ami). **Stan gry**: kod na `main`
  i `README.md`.
- Gdy vault i kod się rozjeżdżają, ADR mówi, jak ma być, a kod, jak jest teraz.
