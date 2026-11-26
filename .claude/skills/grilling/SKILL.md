---
name: grilling
description: >
  Relentless interview that settles every open decision before any work starts. Use when picking up
  a GitHub issue or ticket, when a request or spec leaves room for guessing, before a game-design,
  balance, architecture, Supabase-schema, security or PvP decision, or when the owner says
  "grill" / "zgriluj".
---

# Grilling

Interview the owner until you share one understanding of the work, with nothing silently assumed.
Talk to the owner in Polish. Facts are your job; decisions are the owner's.

## 1. Gather the facts first

Before the first question, read everything you can look up yourself:

- the issue: body, every comment, linked issues and PRs (GitHub MCP `issue_read`, `pull_request_read`);
- the code the work touches (`AGENTS.md` maps it), its tests and the `README.md` "Stan" section;
- the vault notes on the topic and every ADR in `docs/castle-defender-vault/ADR/` that touches it.

For a broad lookup, dispatch an `Explore` subagent and keep asking the questions that do not depend
on its answer. Ask the owner only what no file, command or issue can answer.

## 2. Map the design tree

Every decision branches into the decisions that hang off it. The **frontier** is every decision
whose prerequisites are already settled: questions you can ask now without guessing earlier answers.

When a decision touches balance, economy, PvP, rewards or player data, add a **pre-mortem** branch:
"it is three months later and this failed — why?" and a **red-team** branch: "how does a cheating
player abuse it?" (see `pvp-anti-cheat`). Turn the strongest failure into a question with a
mitigation as your recommendation.

## 3. Ask in rounds

Ask the whole frontier in one round, then wait. Format:

```
❓ **Q1 - <krótki tytuł>**: <pytanie, kontekst, opcje>

➡️ <twoja rekomendacja>

---
```

- Every question carries your recommended answer, worded so "tak" accepts it. Shorthand replies
  ("1 tak, 3b") are fine.
- Each answer reshapes the tree: recompute the frontier and ask the next round. A question that
  depends on one still open this round waits for a later round.
- A question the owner skipped stays on the frontier: ask it again next round, marked as unanswered.
- An answer that opens new branches (a new file, a new process, a new rule) gets its own follow-up
  questions about where, format and scope.
- Write questions in the chat as a numbered list; one round may hold any number of questions.

**On a ticket, always run at least one round.** When the ticket leaves nothing open, the round is
your list of assumptions (scope, seams to test, out of scope, numbers you will use), each one
accepted by "tak".

## 4. Done

The grilling is done when the frontier is empty **and** the owner confirms you understand each
other. Write no code before that. Then record the result:

1. **Comment "Ustalenia" on the issue** (when there is one): each decision on one line, linked
   to its ADR when it has one, with the footer your harness requires for GitHub comments.
2. **ADR for every decision that is hard to reverse or changes the design**: mechanics, the balance
   model, architecture, Supabase schema, security and PvP, rules of work. Call the `adr` skill.
   Small settlements (a button label, a single tuning number) live only in the comment.
3. Continue with the next step: `implement` for a ticket, `to-spec` for a larger idea.
