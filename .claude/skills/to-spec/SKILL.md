---
name: to-spec
description: Turn a grilled conversation into a spec published as a GitHub issue.
disable-model-invocation: true
---

# To spec

Synthesize what the conversation already settled into a spec. Run no new interview: when a gap
shows up while writing, stop and call the Skill tool with "grilling" for that gap only.

## Steps

1. **Read the ground.** The code the feature touches (`AGENTS.md`), the vault notes and the ADRs
   for the area. Use the project's own words for buildings, units, epochs and resources (vault,
   `scripts/world/*_types.gd`).
2. **Propose the test seams.** A **seam** is the public boundary the tests observe: a logic class
   such as `Economy`, `BuildGrid`, `Research` or `Battle`, never a UI node's
   internals. Prefer existing seams and the highest one possible; the ideal number is one. Give each
   seam one line on what it catches and what it misses, and confirm them with the owner.
3. **Draft the spec** from the template, in Polish, and show it to the owner.
4. **Publish after approval** as a GitHub issue in `shivetay/castle_defender`. Use only labels that
   already exist in the repo. Post the issue link in the chat.

Done when: the issue exists, every decision in it is either in the spec or linked to an ADR, and
every seam was confirmed.

## Template

```markdown
## Problem

Problem z perspektywy gracza.

## Rozwiązanie

Rozwiązanie z perspektywy gracza.

## Historyjki gracza

1. Jako <gracz / obrońca offline / atakujący>, chcę <funkcja>, żeby <korzyść>.
(Długa lista, wszystkie przypadki: pierwsze uruchomienie, brak zasobów, epoki, offline, PvP.)

## Decyzje implementacyjne

- Moduły do zbudowania lub zmiany i ich interfejsy (bez ścieżek plików i kodu: szybko się starzeją).
- Zmiany zapisu gry i schematu Supabase.
- Linki do ADR-ów: [[ADR/NNNN-...]] / `docs/castle-defender-vault/ADR/NNNN-...md`.

## Decyzje testowe

- Szwy testowe (uzgodnione) i co każdy łapie.
- Determinizm: ten sam seed → ten sam wynik.
- Wzór: podobne istniejące testy w `tests/`.

## Bezpieczeństwo

Co klient może, a czego nie; co liczy albo weryfikuje serwer. „Nie dotyczy”, gdy nie dotyczy.

## Poza zakresem

## Uwagi
```
