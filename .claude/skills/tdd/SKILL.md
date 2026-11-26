---
name: tdd
description: >
  Test-first red → green loop for Castle Defender's headless Godot tests. Use when building or
  fixing game logic (world, economy, research, battle, save, net), when a bug needs a regression
  test, or when the owner mentions TDD or red-green.
---

# TDD

One slice at a time: one failing test at an agreed seam, the least code that turns it green, repeat.

## The test harness

- Tests live in `tests/test_<nazwa>.gd`, `extends TestCase`. Every `test_*` method ends with
  `return true`; a method that crashes halfway returns null and counts as failed.
- Assertions: `assert_eq(actual, expected, label)`, `assert_true(value, label)`; labels in Polish.
- Run one file: `godot --headless --path . --script res://tests/run_tests.gd -- test_<nazwa>`.
  Run everything at the end: `bash .github/scripts/run_checks.sh`.
- Copy the structure of a nearby test (`test_pixel_canvas.gd` is the minimal one).

## Seams

A **seam** is the public interface a test observes: `Economy`, `BuildGrid`, `TerrainMap`,
`Research`, `Battle` (the simulation), a `SaveGame` round trip. Test only at seams agreed with the owner
during grilling or `to-spec`. A UI test observes what the player sees through the panel's public
API, never its private nodes.

## Rules of the loop

- **Red first.** Write the test, run it, see `FAIL` for the reason you expect. A test that passes
  before the code exists proves nothing.
- **Green with the least code.** No speculative features, no code for the next test.
- **Determinism is a test, not a hope.** For anything seeded (terrain, battle, bots), run it twice
  with the same seed and `assert_eq` the results; run with another seed and check they differ where
  they should. Battle logic runs in fixed steps without rendering.
- **Expected values come from an independent source**: a worked example, a number from the ticket,
  ADR or `Balans.md`, a known-good literal. An assertion that recomputes the value the way the code
  does passes by construction.
- **Refactor after green**, during self-review, with the tests staying green.

## Smells in a test

- It breaks on a refactor that kept behaviour (coupled to internals).
- It asserts a constant against itself (tautology).
- All tests written first, all code after (horizontal slicing): it tests the imagined shape,
  not the behaviour.
