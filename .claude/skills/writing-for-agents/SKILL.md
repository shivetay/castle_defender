---
name: writing-for-agents
description: >
  How to write documents agents read. Use when creating or editing a skill, `CLAUDE.md`,
  `AGENTS.md`, `.claude/agents/*`, `.cursor/*` or `docs/PRACA-Z-AI.md`.
---

# Writing for agents

A document for an agent works when every run takes the same path through it.

## Pointers

A **pointer** is a line in always-loaded context that names other material and the condition for
reading it: a skill's `description`, a row in the `CLAUDE.md` skill table. Its wording decides when
the agent reaches the material.

- Lead with the word that triggers it.
- One trigger per distinct case; synonyms of one case are one trigger.
- Every word of an always-loaded pointer costs on every turn: prune hardest here.

## Invocation

- **Model-invoked** skill (has a `description` with triggers): the agent fires it itself, other
  skills can call it. Costs context on every turn.
- **User-invoked** (`disable-model-invocation: true`, one-line human-facing description): only the
  owner typing `/name` fires it. Zero context cost; the owner has to remember it exists, which is
  what `docs/PRACA-Z-AI.md` is for.

Make a skill model-invoked only when the agent or another skill must reach it alone.

## Structure

- **Steps** (ordered actions) first, **reference** (rules, templates) after or behind a pointer to
  a sibling file. Inline what every case needs; move out what only some cases reach.
- Every step ends on a **completion criterion** the agent can check ("every affected note links to
  the ADR"), never a vague one ("understanding reached").
- Keep one concept's definition, rules and caveats under one heading.

## Words

- Use a **leading word** the model already knows (_frontier_, _seam_, _tracer bullet_, _pre-mortem_)
  and repeat the word, not its definition.
- State the behaviour you want. A prohibition earns its place only as a hard guardrail, and then
  next to the positive target.

## Pruning

- One meaning, one place. `CLAUDE.md` holds the rules; skills point at it instead of restating it.
- Leave lookups to the environment (scripts, file layout, `--help`); write down only what cannot
  be looked up: conventions, reasons, gotchas.
- Delete every sentence that changes nothing compared with the model's default.
- When `CLAUDE.md` and a skill disagree, `CLAUDE.md` wins: fix the skill.
