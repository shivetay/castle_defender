# Claude Code — routing modeli (Castle Defender)

Główne reguły projektu są w `CLAUDE.md` w katalogu głównym. Ten plik mówi tylko,
**którego agenta / modelu** używać.

## Tabela routingu

| Zadanie | Agent | Model | Uwagi |
| --- | --- | --- | --- |
| Analiza issue (Jira / GitHub), triage, labelki | `issue-triage` | `haiku` | Bez ciężkiej edycji kodu |
| Aktualizacja docs / vault Obsidiana, statusy | `issue-triage` | `haiku` | Krótkie diffy dokumentacyjne |
| Zamykanie issue, podsumowanie stanu / PR | `issue-triage` | `haiku` | Komentarze, checklisty, status |
| Feature, bugfix, refactor, merge conflicts | `implementer` | `opus` | Kod gry, testy, CI |
| Niepewne / mieszane (docs + kod) | `implementer` | `opus` | Gdy wchodzi logika GDScript |

## Zasady

1. **Domyślnie lekki model** (`issue-triage` / `haiku`), jeśli nie trzeba zmieniać logiki gry.
2. **Silny model** (`implementer` / `opus`) przy każdej zmianie w `scripts/`, `scenes/`,
   `tests/`, `project.godot` albo przy konfliktach merge.
3. Nie uruchamiaj `implementer` do samego czytania issue albo aktualizacji vaultu.
4. Nie uruchamiaj `issue-triage` do implementacji feature’ów ani napraw bugów.

Agenci: `.claude/agents/issue-triage.md`, `.claude/agents/implementer.md`.
