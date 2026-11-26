---
name: handoff
description: Compact the current session into a handoff document another agent can continue from.
argument-hint: "What will the next session do?"
disable-model-invocation: true
---

Write a handoff document so a fresh agent (Claude Code, Cursor, another session) can continue.

- Save it outside the repo, in the session's scratchpad or `$TMPDIR`, and give its full path.
- Open with the goal of the next session (the argument, when given) and tailor the rest to it.
- Reference rather than repeat: issues, PRs, ADRs, branches, commits by number or path.
- Include: what is done, what is decided (with ADR links), open questions still on the grilling
  frontier, what is unverified (no Godot, needs the phone), and the exact next step.
- End with "Sugerowane skille": which skills the next agent should call first.
- Redact secrets, keys, tokens and personal data.
