---
name: implement
description: >
  Takes a GitHub issue from first read to an open, watched PR: grilling, branch, test-first code,
  checks, security review, PR. Use when asked to do, take or fix an issue or ticket ("zrób #12",
  "weź ticket"), or to build a spec's tickets.
---

# Implement

## Steps

1. **Fetch the issue** (GitHub MCP `issue_read`: body and comments) and state its number and
   title. When the reference is ambiguous, ask which issue.
2. **Grill.** Call the Skill tool with "grilling". Continue only once its frontier is empty, the
   owner confirmed, the "Ustalenia" comment is on the issue and the ADRs are written.
3. **Branch** from the current `origin/main` with a descriptive name (`feat/...`, `fix/...`;
   rules in `CLAUDE.md`). A session that came with a random branch name works on the descriptive one.
4. **Build test-first** at the seams agreed in the grilling: call the Skill tool with "tdd".
   A decision that surfaces mid-build (a new mechanic, a number nobody settled) stops the build:
   grill that one question, then continue.
5. **Check** with `bash .github/scripts/run_checks.sh` (Godot via `bash .github/scripts/install_godot.sh`).
   Read the log, not the exit code. When Godot cannot run, say so in the summary and in the PR.
6. **Update docs**: `README.md` "Stan" / "Następny etap" after a stage; ADRs and vault through the
   `adr` skill; the affected folder's `README.md` when a key file appears.
7. **Review your own diff**: security first with the `security-review` skill (and `/security-review`
   when the diff touches `supabase/`, network code, saves, login, CI or `export_presets.cfg`), then
   correctness, determinism, tests and style.
8. **Ship**: small Polish commits, push, PR to `main` from `.github/pull_request_template.md` with a
   Polish player-facing title. `Closes #N` only when the merge fully closes the issue. Subscribe to
   the PR and work every review comment and CI failure with new commits on the same branch.

Done when: the PR is open, CI is green or its failure is explained, and the PR is watched.
