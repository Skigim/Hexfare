# Contributing to Hexfare

Hexfare is a framework to iterate on, so small, focused changes are the easiest to review.

## Setup and tests

Install Godot 4.7 (standard build). Run all headless tests with `.\tools\run_tests.ps1`
(about 25 s). `-Only <name fragment>` runs one suite. On Linux/macOS use `GODOT=<path> tools/run_tests.sh [fragment]`.
GitHub Actions runs the same headless suites on every push to `main` and every PR. The UI smoke test needs a window:
`godot --path . res://tests/ui_smoke_test.tscn`. README.md has the details.

## Architecture rules

These are in CLAUDE.md and worth reading before a code change:

- `Game` is the only code that mutates `GameState`; UI and AI both go through its action methods.
- Rules are static modules under `scripts/rules/`; the UI calls them for previews.
- The view never mutates state. It re-syncs on `Game.changed`.
- All randomness goes through `state.rng`, so games stay deterministic.
- Anything saved must be JSON-safe.
- Content and balance live in `data/*.json`, not in code.
- New test suites go in `SUITES` in `tests/run_tests.gd`.

## Workflow

1. Pick or open an issue. Issues marked `needs-design` need a short design discussion first.
2. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `content/<topic>` or `art/<topic>`.
3. Keep the tests green and add tests for new rules. Include a screenshot for UI changes.
4. Open a PR that says `Closes #<n>`. PRs are squash-merged.

## Labels and milestones

- **Type**: `bug`, `feature`, `content` (data-only), `balance`, `tech-debt`, `docs`, `infra`
- **Area**: `area:rules`, `area:ai`, `area:ui`, `area:view`, `area:art`, `area:data`, `area:tests`
- **Priority**: `p1-now`, `p2-next`, `p3-later`
- **Status**: `blocked`, `needs-design`

Milestones are SemVer versions with a theme (`v0.2.0` and so on). Closing a milestone means
tagging `vMAJOR.MINOR.PATCH` and publishing a GitHub Release.

## Licence

By contributing you agree your code is released under the MIT licence in `LICENSE`. Art you add
should be CC0 or your own, with its licence file next to it.
