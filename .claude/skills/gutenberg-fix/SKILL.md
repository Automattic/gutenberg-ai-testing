---
name: gutenberg-fix
description: This skill should be used ONLY when the user explicitly invokes the `/gutenberg-fix` slash command. Takes a `/gutenberg-repro` report whose verdict is `Reproduced`, diagnoses the root cause, and explores one or more candidate patch shapes in parallel inside isolated git worktrees. The winning worktree's single test+fix commit is cherry-picked onto a `fix/issue-<N>` branch in the main checkout, and a `fix-report.md` is written next to the original `report.md` with red-green evidence. Refuses early if the report's verdict is anything other than `Reproduced`. Do not auto-fire on conversational mentions of bugs, fixes, or patches.
version: 0.2.0
argument-hint: <report-path | issue-number>?
arguments:
  - name: target
    required: false
    description: |
      What to fix. Accepts:
      - An absolute path to a `report.md` from `/gutenberg-repro`, e.g. `/tmp/gutenberg-repro/12345-20260520-141022/report.md`.
      - A bare GitHub issue number (assumed `WordPress/gutenberg`): `12345`.
      - A short ref: `WordPress/gutenberg#12345`.
      - Omitted entirely: the skill picks the most recently modified `report.md` under `/tmp/gutenberg-repro/`.
---

# Gutenberg Fix

Take a confirmed-reproduced Gutenberg bug and explore a fix end-to-end. The skill is paired with `/gutenberg-repro`: it consumes that skill's report and never re-runs the reproduction itself.

The mechanism is **git worktrees + isolated `Agent` invocations**. The parent skill diagnoses, writes a single controlled e2e spec, then dispatches one or more worktree agents — each tries a different candidate patch shape, runs the test red-then-green, and commits test + fix as one commit on its worktree branch. The parent aggregates outcomes and cherry-picks the winner onto `fix/issue-<N>` in the main checkout. The main checkout is never mutated during exploration.

## Prerequisites

- Current working directory is the WordPress/Gutenberg checkout.
- A `/gutenberg-repro` report exists on disk with verdict `Reproduced`.
- `gh` CLI authenticated.
- Node, npm, composer installed.

If any prerequisite is missing, stop and tell the user.

## Workflow

Follow each step in order. Track progress with TodoWrite. Do not skip steps.

### Step 1 — Resolve the target report

Resolve `target` (see frontmatter) into an absolute path to a `report.md`:

- **Explicit path** → use as-is. Refuse if the file doesn't exist.
- **Issue number / short ref** → glob `/tmp/gutenberg-repro/<number>-*/report.md`, pick newest by mtime.
- **Omitted** → glob `/tmp/gutenberg-repro/*/report.md`, pick newest by mtime overall (`ls -t /tmp/gutenberg-repro/*/report.md | head -1`).

If no matching report is found, stop and tell the user to run `/gutenberg-repro` first.

Read the report. Parse:

- The `**Verdict:**` line. If it is anything other than `Reproduced`, refuse with a one-line explanation (e.g., "report's verdict is `Not reproduced` — this may already be fixed on trunk; out of scope for `/gutenberg-fix`"). Do not proceed.
- The issue number, issue title, and issue URL.
- The `**Tested against:**` SHA — record it for the fix report.
- The Setup section's allocated ports (the `<port>` / `<tests-port>` pair from `/gutenberg-repro`) — informational only; this skill allocates its own ports for worktree agents.
- The repro plan (preconditions, steps, expected, actual).
- The execution log of the attempt that reproduced the bug.

### Step 2 — Verify entry state

Refuse to proceed without explicit user consent under any of:

- `git status --porcelain` is non-empty (dirty working tree). The worktree agents branch off `HEAD`, and a dirty tree would mean their starting point includes the user's in-progress work.
- Current branch is not `trunk` (`git rev-parse --abbrev-ref HEAD`).
- A branch named `fix/issue-<N>` already exists locally. Quote the last commit message on it (`git log -1 --format='%s' fix/issue-<N>`) so the user can decide whether to delete it or rename.

Never run `wp-env destroy`, `wp-env clean`, `git reset --hard`, branch switches, or any destructive operation without explicit user consent.

### Step 3 — Diagnose the root cause

Form a hypothesis about where the bug lives, using:

1. **The report's repro plan and execution log** — what step produced the bug, what the observed final state looked like, any filtered console errors.
2. **The `bug-state.png` screenshot** in the report's temp dir.
3. **Code reading.** Trace from the symptom toward the cause. Use the Gutenberg layering as a navigation hint: `block-editor` (generic) → `editor` (post-aware) → `edit-post`/`edit-site` (screens). Console errors often name the file directly. If a hypothesis can only be confirmed by in-browser observation, the right move is to *encode that observation in the e2e test*, not to drive the browser interactively.

Produce a hypothesis with these fields:

- **Root cause:** one or two sentences. Reference the relevant `file:line`.
- **Why this causes the symptom:** the chain from cause to user-visible effect.
- **Proposed patch shape:** what change you would make and where. Do not write code yet.
- **Test approach:** how a Playwright spec would assert the bug exists. Be specific about selectors, expected DOM state, and the assertion. The spec is the verification harness for every candidate in Step 5, so it must be the strongest available expression of the bug.
- **Observable via Playwright?** `yes` or `no`, with one-line reasoning. Bugs in the REST contract that aren't surfaced in the UI, internal data-layer regressions not visible in the editor, or timing/race conditions are common reasons for `no`.
- **Confidence:** `high` or `low`. Mark `low` when **any** of:
    - More than one file could plausibly host the root cause and the symptom doesn't disambiguate.
    - The repro-report execution log lacks the console / network errors or observable state changes the diagnosis would need.
    - The patch crosses a Gutenberg layering boundary (`block-editor` ↔ `editor` ↔ `edit-post`/`edit-site`) in a non-obvious direction.
    - The test approach asserts on URL/DOM state the action could reach via multiple paths (could pass for the wrong reason).
    - Any architectural smell check below is `yes`.
- **Architectural smell checks** (yes/no, write the answers into the hypothesis):
    1. Does the patch change a function/callback signature other consumers depend on?
    2. Does the patch change a leaf-package API such that hosts must opt in to keep the bug fixed?
    3. Does the patch move a callback's primary effect from in-place execution into an optional notification hook (delegation smell)?
    4. Does the patch put WordPress-specific logic into `block-editor`, or `core-data` calls into `block-editor`?

If confidence is `low` or any smell is `yes`, generate **2–3 distinct alternative patch shapes** before the checkpoint — different enough that they would touch different files / use different mechanisms (e.g., dispatch from inside the action vs. full-page navigation via `window.location.href` vs. registry-level override at the host). Picking one is the user's job in Step 4; generating them is the skill's.

Do not start writing test or patch code in this step. Diagnosis only.

### Step 4 — Checkpoint (one user gate, parameterised by confidence)

Present the hypothesis to the user. The shape of what you present depends on confidence:

**Confidence `high`, no smells, observable=yes** → no pause. Summarise the hypothesis in chat for transparency, then proceed straight to Step 5 with N=1 (a single worktree agent for the single candidate). This preserves the fast path.

**Confidence `low` or any smell `yes`** → present the hypothesis, the smell-checklist answers, and the 2–3 alternative patch shapes you generated in Step 3. Offer the user four choices via `AskUserQuestion`:

- **(a) Explore them all in parallel** (default). Proceed to Step 5 with N = the number of candidates you generated. Each is dispatched to its own worktree agent concurrently.
- **(b) Pick one to pursue.** User selects a single candidate; Step 5 runs with N=1.
- **(c) Push back.** User describes a hypothesis Claude missed; restart Step 3 with that steer in mind.
- **(d) Abort.** Skill stops; no worktrees, no branch, no commits. User picks up manually.

**Observable via Playwright is `no`** (Tier-1 fallback) — present hypothesis + reasoning, offer three choices:

- **(a) Abort.** Same as above.
- **(b) Tier-1 fallback.** Proceed with a single worktree agent that applies the patch and produces only a fix commit (no test). The fix-report uses verdict `Tier-1 fixed`.
- **(c) Push back.** User describes a test approach Claude missed; restart Step 3.

This is the only user gate in the workflow. Errors during Step 5 or later are handled by the iteration discipline (Step 6) or terminate with a structured failure report (Step 7) — they do not prompt the user mid-run.

### Step 5 — Dispatch worktree agents

This step never mutates the user's main checkout. All work happens inside worktrees created and cleaned up by the `Agent` tool's `isolation: "worktree"` mode.

**5a. Prepare the controlled e2e spec.** Pick the spec location:

```
test/e2e/specs/<area>/issue-<N>-<slug>.spec.js
```

Areas: `admin`, `editor`, `interactivity`, `preload`, `site-editor`, `widgets`. Pick the one whose name best matches where the bug lives. `<slug>` is a kebab-case condensation of the issue title (≤ 40 chars). Tests use `require( '@wordpress/e2e-test-utils-playwright' )` — see existing files in the area folder for the local conventions. The assertions must be the strongest available expression of the bug; prefer accessible-name selectors (`page.getByRole(...)`) over CSS selectors.

Write the spec content **in memory** (don't touch the main checkout's filesystem). The same spec content is handed to every worktree agent so the test is the controlled variable across candidates.

**5b. Allocate ports.** Each worktree agent runs its own wp-env. Allocate `2 × N` random free ports up front so siblings don't collide:

```bash
python3 -c 'import socket
def f():
    s = socket.socket(); s.bind(("", 0)); p = s.getsockname()[1]; s.close(); return p
ports = [f() for _ in range(2 * <N>)]
print(*ports)'
```

Pair them: agent *i* gets `WP_ENV_PORT=ports[2i]` and `WP_ENV_TESTS_PORT=ports[2i+1]`.

**5c. Dispatch agents in parallel.** For each candidate patch shape, invoke `Agent` once with `isolation: "worktree"`. Send them in a single message so they run concurrently. Each agent's prompt is self-contained and must include:

- Absolute path to the repro report (`READ-ONLY; never mutate`).
- The spec file path (`test/e2e/specs/<area>/issue-<N>-<slug>.spec.js`) and the **full spec content** to write inside the worktree.
- A precise natural-language description of the candidate patch shape this agent should implement, naming file paths and the kind of change.
- The pre-allocated `WP_ENV_PORT` and `WP_ENV_TESTS_PORT` for this agent.
- The required commit-message template (see Step 6).
- The required report-back shape (see Step 5d).
- The forbidden actions list (see Step 5e).

**5d. Each agent's loop** (encoded in the prompt):

1. `npm install` only if `node_modules` doesn't exist (the worktree starts as a fresh checkout; if the parent's `node_modules` was symlinked by the harness, skip — check before running).
2. `npm run build` (~40s; required because the e2e test runs against built assets).
3. `WP_ENV_PORT=<port> WP_ENV_TESTS_PORT=<tests-port> npm run wp-env start -- --runtime=playground` (start the agent's own wp-env).
4. Write the spec content to `test/e2e/specs/<area>/issue-<N>-<slug>.spec.js`.
5. Run the e2e test:
   ```bash
   WP_ENV_PORT=<port> WP_BASE_URL=http://localhost:<port> \
     npm run test:e2e -- test/e2e/specs/<area>/issue-<N>-<slug>.spec.js
   ```
   The test **must fail** (red). If it passes on unfixed code, report `outcome: error, reason: test passes on unfixed code` and stop. Do not commit anything.
6. Apply the candidate patch shape to the named source files.
7. If any JS/TS files changed, `npm run build` again. PHP files need no rebuild.
8. Re-run the e2e test (same command). One of:
   - **Green** → format the changed files (`npm run format -- <paths>`; `vendor/bin/phpcbf <paths>` for PHP); stage *test + source files together*; create a single commit with the message template from Step 6. Report `outcome: green` with branch name, commit SHA, and `git diff --stat HEAD~1` excerpt.
   - **Red** → report `outcome: red` with the assertion excerpt. Do not commit. Do not iterate inside the agent.
   - **Error** (build failure, wp-env crash, etc.) → report `outcome: error` with the error excerpt.

**5e. Forbidden actions in worktree agents** (encode in every prompt):

- **No Playwright MCP usage** (`mcp__plugin_playwright_playwright__*` tools). The e2e test is the harness.
- No commits to anything other than the worktree's auto-created branch.
- No pushing, force-pushing, amending, or rewriting history.
- No more than one commit per agent.
- No internal iteration. If the first patch attempt doesn't go green, report red and let the parent decide.
- No `wp-env destroy`, `wp-env clean`, or any other destructive command.

### Step 6 — Aggregate outcomes

Collect the agents' results (you receive them as Agent tool messages once each completes).

**Single agent (N=1).**

- `green` → proceed to 6a (cherry-pick + verify).
- `red` or `error` → enter the iteration round (6c) if budget remains, otherwise Step 7.

**Multiple agents (N>1).**

- One or more `green` → 6b (user picks winner).
- All `red` or `error` → 6c (iteration round) if budget remains, otherwise Step 7.

**6a. Cherry-pick the winning worktree's commit.**

```bash
git switch -c fix/issue-<N> trunk
git cherry-pick <commit-sha-from-agent>
git log --oneline -1
```

The main checkout is now on `fix/issue-<N>` with the single combined commit. Do not push.

**6b. Multiple greens — let the user pick.** Present each candidate side-by-side via `AskUserQuestion` (or summarise in chat if the user has expressed they want to make the call themselves). For each green candidate include:

- Files touched and `--stat` summary.
- The candidate patch shape (one-line).
- The worktree path and branch name (so the user can `cd` in and inspect interactively).

User picks one; cherry-pick that one per 6a.

**6c. Iteration round.** Total iteration budget across the whole run: 2 iterations beyond the initial worktree round. An iteration is one of:

- **Patch refinement.** Same hypothesis, narrower patch shape. Spawn a new worktree agent (N=1) with the refined shape.
- **Hypothesis swap.** Different root cause. Save all rejected patches under `<temp-dir>/attempts/attempt-<n>.patch` (one per agent that produced one), re-enter Step 3 to generate fresh candidates, then return to Step 5.
- **Test refinement.** If every agent reported `outcome: error, reason: test passes on unfixed code`, the spec is wrong (asserts on something the bug doesn't break). Rewrite the spec in memory and re-enter Step 5 with the same candidates.

Patch refinement and hypothesis swap each count against the budget. The fix report's `Iteration history` labels each iteration's kind. Past 2 iterations without a green winner → Step 7.

Infrastructure errors (the harness or wp-env crashing for unrelated reasons) are not iterations — surface them immediately and stop the run with a clear message.

### Step 7 — Stuck (failure path)

Reached only when the iteration budget is exhausted without any green worktree.

Save every distinct attempted patch under `<temp-dir>/attempts/`. Save the spec content under `<temp-dir>/attempts/spec.js` (it was never committed in any worktree because no green was reached). **No `fix/issue-<N>` branch is created in the main checkout** — the user's working state stays as it was at Step 2.

Write the fix report (Step 8) with verdict `Stuck`. The report's `Notes` section must explain where the run got stuck and what the most promising lead is for human follow-up.

### Step 8 — Write the fix report

Write `fix-report.md` next to the original `report.md` in `/tmp/gutenberg-repro/<issue-number>-<timestamp>/`. Render using `references/fix-report-template.md`.

If the run succeeded, also write the final accepted diff:

```bash
git diff trunk..fix/issue-<N> -- '*.js' '*.php' '*.ts' '*.tsx' \
  > /tmp/gutenberg-repro/<issue-number>-<timestamp>/final.patch
```

Print the absolute path to `fix-report.md` in the conversation, along with a one-line summary of the verdict and a `cd` hint for inspecting the temp dir.

### Step 9 — Leave running

Do not stop the dev wp-env that `/gutenberg-repro` left running. Do not switch off the `fix/issue-<N>` branch in the main checkout. Do not delete the temp dir. Do not manually clean up worktrees — the `Agent` tool's isolation auto-cleans worktrees that produced no commits; modified worktrees stay on disk and the path/branch names are in the fix report so the user can `cd` in to inspect or delete them.

The user typically wants to:

- Inspect the cherry-picked fix on `fix/issue-<N>`.
- Compare it against an alternative candidate worktree the parent didn't pick.
- Continue iterating manually on top of the chosen commit.

Leaving everything in place makes those workflows one command away.

## Rigid rules

These constraints override any apparent shortcut:

- Never use Playwright MCP tools (`mcp__plugin_playwright_playwright__*`) inside this skill or its dispatched agents. The e2e test is the verification harness.
- Every patch exploration runs inside an isolated git worktree via `Agent` with `isolation: "worktree"`. The main checkout is only mutated by the final cherry-pick onto `fix/issue-<N>` after a green is found.
- Test + fix go in a single combined commit (the worktree agent's commit), not two separate commits.
- Never mutate the original `report.md` produced by `/gutenberg-repro`. Write new files alongside it; do not edit existing files in its temp dir.
- Never push to a remote. The `fix/issue-<N>` branch stays local.
- Never `--amend` an existing commit; create new commits if iteration is needed.
- Never commit without first running `npm run format` (for JS/TS) or `vendor/bin/phpcbf` (for PHP) on the changed files. The worktree agent does this before staging.
- Never run `git reset --hard`, `git checkout` of branches, `git stash`, `wp-env destroy`, `wp-env clean`, or any destructive command without explicit user consent.
- Never auto-fire. Only run when the user explicitly types `/gutenberg-fix`.
- Never post to GitHub. The fix and the report stay on the local branch and on disk; publication is a separate, user-initiated action.

## Additional resources

- **`references/fix-report-template.md`** — Exact structure for `fix-report.md`.
- **`../gutenberg-repro/references/wp-env-recipes.md`** — Available if the fix requires additional preconditions to verify inside a worktree.
