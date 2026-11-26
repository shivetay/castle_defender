# ADR 0001: Grillowanie i ADR w pracy z AI

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** brak

## Kontekst

Agenci AI dostawali tickety i niejasne prośby, a `CLAUDE.md` kazał im w takiej sytuacji
„zaproponować jedną opcję”. Decyzje projektowe lądowały w różnych miejscach vaultu
(np. „decyzja 23.11.2026” w [[Otwarte pytania]]) bez jednego źródła prawdy. Właścicielka chce,
żeby wszystko, co niejasne, było „zgrillowane”, zanim powstanie kod.

## Decyzja

- Po przeczytaniu ticketu na GitHubie agent zawsze grilluje: sam ustala fakty z issue, kodu, vaultu
  i ADR-ów, a potem zadaje pytania w rundach. Przy każdym pytaniu podaje rekomendację,
  a „tak” ją akceptuje. Zawsze jest co najmniej jedna runda, choćby z samymi założeniami.
  Kod powstaje dopiero po potwierdzeniu.
- Wynik trafia do komentarza „Ustalenia” w issue.
- Decyzje trudne do odwrócenia albo zmieniające projekt gry (mechanika, model balansu,
  architektura, schemat Supabase, bezpieczeństwo i PvP, zasady pracy) dostają ADR w
  `docs/castle-defender-vault/ADR/`. Na podstawie ADR-ów aktualizowany jest vault.
- Przy balansie, ekonomii, PvP i danych graczy grillowanie zawiera pre-mortem i red team.
- Skille pracy (`grilling`, `grill-me`, `adr`, `to-spec`, `to-tickets`, `implement`, `tdd`,
  `handoff`, `writing-for-agents`) są pisane po angielsku. Rozmowa z właścicielką, komentarze,
  ADR-y i vault są po polsku.
- Specyfikacje i tickety żyją w GitHub Issues (specyfikacja jako rodzic, tickety jako sub-issues
  z „Blokowane przez”).

## Rozważane opcje

- **Grillowanie przy każdym tickecie, ADR w vaulcie** (wybrana): jedno źródło decyzji, linki
  Obsidiana działają, `.gdignore` vaultu już obejmuje folder.
- **Jedna proponowana opcja przy niejasności** (dotychczasowa reguła): szybsza, ale zostawia
  ciche założenia.
- **`GLOSSARY.md` + ADR-y w `docs/adr/` poza vaultem**: dubluje rolę vaultu.
- **Okienka `AskUserQuestion`**: maksymalnie 4 pytania naraz, za mało na rundę.

## Konsekwencje

- Start pracy nad ticketem trwa dłużej (runda pytań), ale kod nie opiera się na domysłach.
- Każda większa decyzja ma plik ADR, a vault linkuje do niego.
- Dotychczasowe ustalenia z [[Otwarte pytania]] zostają, jak są; przeniesienie ich do ADR-ów
  to osobny ticket.
- Z repozytoriów skilli Jeffallan i gamedev nie dochodzą nowe skille; skille gamedev są aktualne
  (commit `c6ca6c4`).

## Dotknięte notatki

- [[00 Start]]: link do indeksu ADR-ów.
- `CLAUDE.md`, `docs/PRACA-Z-AI.md`, `.cursor/`: reguły pracy agentów.
