# Fix report template

Render `fix-report.md` using exactly the structure below. Replace placeholders in angle brackets. Omit sections that don't apply (e.g., iteration history when only the initial worktree round was used), but always keep the header and verdict line.

The first non-blank line under the title must be `**Verdict:**` so the report is greppable.

```markdown
# Fix report: issue #<number> — <issue title>

**Verdict:** <Fixed | Tier-1 fixed | Stuck>
**Issue:** <full URL>
**Repro report:** `./report.md`
**Branch:** `fix/issue-<N>` (local only; not pushed)
**Base:** trunk @ <short SHA from repro report>
**Worktrees:** <N> dispatched <(parallel | single)>
**Iterations used:** <0–2>
**Date:** <ISO 8601 timestamp>

## Hypothesis

**Root cause:** <one or two sentences, with `file:line` reference>

**Why this causes the symptom:** <chain from cause to user-visible effect>

**Observable via Playwright:** <yes | no — if "no", which Tier-1 fallback path was taken and why>

**Hypothesis confidence:** <high | low — if "low", `Notes` must explain why>

**Architectural smell checks:**

| # | Question | Answer |
| - | -------- | ------ |
| 1 | Does the patch change a function/callback signature other consumers depend on? | <yes / no> |
| 2 | Does the patch change a leaf-package API such that hosts must opt in to keep the bug fixed? | <yes / no> |
| 3 | Does the patch move a callback's primary effect from in-place execution into an optional notification hook (delegation smell)? | <yes / no> |
| 4 | Does the patch put WordPress-specific logic into `block-editor`, or `core-data` calls into `block-editor`? | <yes / no> |

## Alternatives considered

<Omit if confidence was `high` and only N=1 was dispatched.>

- **Candidate A — <one-line shape>.** <Files it would touch. Outcome from its worktree (green / red / error + short reason).>
- **Candidate B — <one-line shape>.** ...
- **Candidate C — <one-line shape>.** ...

## Changes

<Omit if verdict is Stuck (no commit reached the main checkout).>

**Files touched:**
- `packages/<area>/<file>.js` — <one-line description of change>
- `test/e2e/specs/<area>/issue-<N>-<slug>.spec.js` — new e2e regression test

**Diff:** `./final.patch`

## Commit

<Omit if verdict is Stuck.>

- **SHA:** `<sha>` (on `fix/issue-<N>` in the main checkout, cherry-picked from worktree branch `<worktree branch name>`)
- **Message:**
  ```
  <Area>: Fix <one-line summary>

  <2–4 lines describing the root cause and the fix.>

  Adds an e2e regression test in test/e2e/specs/<area>/issue-<N>-<slug>.spec.js
  that fails on unfixed code and passes after this change.

  Fixes #<N>
  ```

## Red-green evidence

<Omit under Tier-1 fallback — replace with a "Manual verification" subsection instead.>

### Before fix (red)

- Worktree: `<absolute path>` (branch `<worktree branch>`)
- Command: `WP_ENV_PORT=<port> WP_BASE_URL=http://localhost:<port> npm run test:e2e -- <spec path>`
- Outcome: failed at `<assertion or step>`
- Excerpt: ```<terse, the assertion error or expect() output>```

### After fix (green)

- Command: <same as above>
- Outcome: passed
- Duration: <wall clock>

### Manual verification (Tier-1 fallback only)

<Replace red-green section under Tier-1.>

- Re-drove the repro plan steps inside the worktree after applying the fix.
- Observed: <free text describing what changed in the editor vs the original `actual` from the repro plan>
- Screenshot: `./fixed-state.png` (if captured)

## Worktree exploration

| Candidate | Worktree path | Branch | Outcome | Diff stat |
| --------- | ------------- | ------ | ------- | --------- |
| A — `<shape>` | `<path>` | `<branch>` | green | `<N files, +X -Y>` |
| B — `<shape>` | `<path>` | `<branch>` | red | `<assertion excerpt>` |
| C — `<shape>` | `<path>` | `<branch>` | error | `<error excerpt>` |

The winning worktree's branch and path are kept on disk so the user can `cd` in to inspect. Worktrees that produced no commits were auto-cleaned by the `Agent` tool's isolation.

## Iteration history

<Omit if no iterations beyond the initial worktree round.>

### Iteration 1

- Kind: <patch-refinement | hypothesis-swap | test-refinement>
- What changed: <one or two sentences>
- Result: <green winner | still red — describe>

### Iteration 2

<same shape; omit if not used>

## Rejected attempts

<Omit if `<temp-dir>/attempts/` is empty.>

- `./attempts/attempt-1.patch` — <one-line reason this was rejected>
- ...

## Notes

<Free text for anything that doesn't fit the structure: surprising file locations, related PRs found during code reading, places where the fix touches a layering boundary that the user should review (e.g., a `block-editor` change with `core-data` smell), gotchas about the test itself (e.g., requires a specific theme), why confidence was `low` if it was, what the most promising lead is if verdict is `Stuck`. Anything a human reviewer should know before promoting this to a PR.>
```

## Notes on filling the template

- **Verdict line:** exactly one of the three values, no qualifiers. Caveats go in `Notes`.
- **Verdict semantics:**
  - `Fixed` — at least one worktree went green; its single test+fix commit was cherry-picked onto `fix/issue-<N>` in the main checkout.
  - `Tier-1 fixed` — non-UI bug; single worktree applied the fix, manually verified inside the worktree, committed without a test (Step 4 (b) Tier-1 path chosen by user).
  - `Stuck` — initial worktree round + iteration budget exhausted without any green. **No `fix/issue-<N>` branch was created in the main checkout.** The `Notes` section must explain where the run got stuck and what the most promising lead is for human follow-up.
- **`./final.patch`:** path is relative to the temp dir (which is also where this report lives). Same convention as `/gutenberg-repro`'s `./bug-state.png`.
- **Worktree paths:** worktrees that made changes survive after the run (the `Agent` tool's isolation only auto-cleans empty ones). The user can `cd` in to inspect interactively, or delete with `git worktree remove <path>`.
- **Layering call-outs:** Gutenberg has a strict three-layer editor architecture (`block-editor` → `editor` → `edit-post`/`edit-site`). If the fix touches `block-editor` with what looks like WordPress-specific logic, flag it in `Notes` so the reviewer can sanity-check the abstraction boundary isn't being broken.
- **Confidence justifications:** when `**Hypothesis confidence:**` is `low`, the `Notes` section must briefly explain which of Step 3's `low` criteria applied. When any architectural smell check is `yes`, `Notes` must briefly justify why the chosen patch shape goes ahead anyway (or why it was the least-bad option).
