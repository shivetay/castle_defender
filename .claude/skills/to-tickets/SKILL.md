---
name: to-tickets
description: Break a spec issue into tracer-bullet sub-issues with blocking edges on GitHub.
disable-model-invocation: true
---

# To tickets

Break a spec (usually a GitHub issue from `to-spec`) into **tickets**: tracer-bullet vertical
slices, each declaring the tickets that block it.

## Steps

1. **Read the source.** The spec issue with every comment, its ADRs, and the code it touches.
   Look for a prefactor that makes the rest easy ("make the change easy, then make the easy change");
   it becomes the first ticket.
2. **Draft vertical slices.**
   - Each slice cuts a narrow but complete path through every layer it needs (world or battle
     logic, save, UI, Supabase), and ends playable or testable on its own.
   - Each slice fits one fresh context window and one branch and PR (`CLAUDE.md`: one branch,
     one coherent change).
   - A wide mechanical change (renaming a resource or building kind everywhere) goes
     expand → migrate in batches → contract, each step its own ticket, so `run_checks.sh` stays green.
3. **Give each ticket its blocking edges**: only the tickets that genuinely gate it.
4. **Quiz the owner.** Show a numbered list: title, "Blokowane przez", what it delivers. Ask whether
   the granularity is right, whether the edges are right, what to merge or split. Iterate until the
   owner approves.
5. **Publish** in dependency order (blockers first) as sub-issues of the spec (`sub_issue_write`),
   so each "Blokowane przez" can cite real numbers. Use only labels that already exist. Leave the
   parent issue unchanged apart from the sub-issue links.

Done when: every approved ticket exists, each is a sub-issue of the spec, and every edge points at
a real issue number.

## Ticket template

```markdown
## Rodzic

#N

## Co zbudować

Zachowanie od początku do końca, z perspektywy gracza, nie lista warstw.

## Kryteria akceptacji

- [ ] Kryterium 1 (sprawdzalne testem albo na telefonie)
- [ ] Test w `tests/test_<nazwa>.gd`, determinizm przy tym samym seedzie

## Blokowane przez

- #N albo „nic (można zaczynać)”
```

Write no file paths or code in tickets: they go stale. A shape that encodes a decision better than
prose (a state machine, a save-format dictionary) may go in, trimmed to the decision.
