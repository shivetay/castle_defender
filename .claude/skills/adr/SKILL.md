---
name: adr
description: >
  Records a settled decision as an ADR in the vault and updates the vault notes it touches. Use
  after grilling settles a hard-to-reverse or design-changing decision (mechanics, balance model,
  architecture, Supabase schema, security, PvP, rules of work), when a decision replaces an older
  ADR, or when the owner asks for an ADR.
---

# ADR

An **ADR** (Architecture Decision Record) is the source of truth for one decision: what was
decided, why, and what it changes. The vault follows the ADRs; the code follows the vault. Whether
something already *is* in the game is still decided by the code on `main`.

ADRs live in `docs/castle-defender-vault/ADR/`, are written in Polish and contain no personal data.

## Steps

1. **Number it.** List `ADR/`, take the next free four-digit number. File name:
   `NNNN-krotki-opis.md` (kebab-case, no Polish characters).
2. **Write it** from the template below. Status `przyjęty` only when the owner confirmed the
   decision; otherwise `proponowany`. Fill "Rozważane opcje" with the options the grilling actually
   weighed, including the rejected ones and why.
3. **Supersede, never delete.** When the new ADR replaces an older one, change only the old one's
   status line to `zastąpiony przez [[ADR/NNNN-...|ADR NNNN]]`. An accepted ADR's body stays as it
   was written.
4. **Update the vault.** For every note listed under "Dotknięte notatki":
   - make the smallest edit that brings the note in line with the decision, in the note's own style,
     with a link `[[ADR/NNNN-krotki-opis|ADR NNNN]]` next to the changed text;
   - in `Otwarte pytania.md`, move the settled question from "Pytania otwarte" to "Ustalone" with
     the date, the issue number and the ADR link;
   - mark facts about the code ("jest w kodzie", `Stan prac.md`) only once the code is on `main`.
5. **Index it.** Add a row to `ADR/README.md` (number, title, status, issue).
6. **Ship it with the change.** ADR and vault edits go in the same branch and PR as the code they
   decide. A decision with no code yet goes in its own `docs/...` branch and PR.

Done when: the ADR file exists, every affected note links to it, the index row is there and
`Otwarte pytania.md` no longer lists the question as open.

## Template

```markdown
# ADR NNNN: <tytuł decyzji>

- **Status:** proponowany | przyjęty | zastąpiony przez [[ADR/NNNN-...|ADR NNNN]]
- **Data:** RRRR-MM-DD
- **Issue:** #N (albo „brak”)

## Kontekst

Jaki problem albo pytanie wymusiło decyzję. Fakty z kodu i vaultu, z linkami.

## Decyzja

Co ustalono, w trybie oznajmującym („Atak ma 3 oddziały w epoce I”). Liczby dokładnie.

## Rozważane opcje

- **Opcja A** (wybrana): dlaczego.
- **Opcja B**: dlaczego odrzucona.

## Konsekwencje

Co się zmienia w grze, kodzie, danych graczy i bezpieczeństwie; co staje się trudniejsze;
co trzeba zrobić dalej (tickety).

## Dotknięte notatki

- [[Nazwa notatki]]: co w niej zmieniono.
```
