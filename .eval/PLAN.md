# Gutenberg-triage skill improvement loop — PLAN

This file is the contract for an autonomous eval loop that improves `.claude/skills/gutenberg-triage/SKILL.md` so the **haiku** model can reliably produce excellent triage results. It is the kickoff doc for any session (initial or post-handoff) that drives the loop.

## Architecture

- **Main session (this agent)** orchestrates an *unbounded* sequence of rounds. The main agent does NOT draft SKILL.md edits, dispatch triage agents, or run the judge directly — those happen inside a per-round sub-agent.
- **Round runner sub-agent** (one per round): reads prior round state, decides + commits the SKILL.md edit, dispatches the 40 triage sub-sub-agents, runs the judge, reverts on regression, appends to `summary.md`, returns a terse JSON status to the main agent.
- **Main agent loop:** after each round, parse the round-runner return; halt on stop conditions; otherwise spawn the next round runner. The loop continues until a stop condition fires or the user interrupts. There is **no round-count cap**.

Sub-agent transcripts are NOT bubbled up to the main agent — only the return JSON is. This keeps main-session context near-flat across many rounds, deferring (but not eliminating) the need for handoff.

## What the main agent does each round

```
loop:
  spawn round-runner sub-agent for round N (using .eval/templates/round-runner-prompt.md)
  parse return JSON
  if halt_reason: write .eval/FINAL-REPORT.md, PushNotification, exit cleanly
  elif main_session_context_utilization >= 50%: invoke handoff skill, exit (user manual restart resumes from round N+1)
  else: N += 1, continue
```

Halt reasons (the main agent acts on these; the round runner only reports them):

- **3 consecutive auto-reverts** (rollback counter hits 3/3).
- **Judge malformed output × 2** (round runner already retried once with a schema reminder).
- **Opus drift** (>40% of issues flagged `opus_flagged_wrong` in a round) — add reason `"opus calibration drift"`.

No other automatic stop. The user interrupts to ship (see "End deliverable" below) or pause.

## What the round runner does (per round)

For round N, the runner:

1. **Inspect state:** read `.eval/PLAN.md` (this file), `.eval/templates/`, the tail of `.eval/summary.md`, the prior round's `.eval/round-(N-1)/judge-report.md` (skip for N=0), and `git log iterate-skill-triage --oneline` for the canonical changelog and rollback-counter inference.
2. **Decide + apply the SKILL.md edit** targeting the top train failure mode from the prior judge report (prioritizing modes with `also_appears_in_holdout: true`). Round 0 makes no edit. Commit `round-N: <subject>` on `iterate-skill-triage`.
3. **Snapshot** the edited SKILL.md to `.eval/round-N/skill-before.md`. Pre-create round-N workspace dirs (`.eval/round-N/{haiku/<num>-runK,opus/<num>}/` for every corpus issue).
4. **Dispatch 40 triage sub-sub-agents** via the byte-identical `.eval/templates/dispatch-prompt.md` wrapper: 3 haiku + 1 opus × 10 issues. Use `subagent_type="general-purpose"` + `model="haiku"`/`"opus"`. Batch as 12 + 12 + 8 + 8 across four messages.
5. **Dispatch the judge** (single opus call) per `.eval/templates/judge-prompt.md` with placeholders `{{ROUND}}=N`, `{{ROUND_DIR}}=.../round-N`, `{{OUTPUT_PATH}}=.../round-N/judge-report.md`, `{{CORPUS_PATH}}=.../templates/corpus.md`, `{{PRIOR_AGGREGATES_PATH}}=.../round-(N-1)/judge-report.md` (or `none` for N=0). Parse YAML frontmatter. If judge output is malformed, retry once with a schema reminder; second failure → return `halt_reason: "judge malformed"`.
6. **Regression handling:** if `regression_check.triggered: true` AND N > 0, `git revert` the round-N commit, then `git commit --amend -m "round-N: REVERTED — <reasons>"`. Compute the consecutive-revert count by walking `git log` backwards from HEAD counting commits whose subject starts with `round-K: REVERTED`. If the count hits 3 → return `halt_reason: "3 consecutive rollbacks"`.
7. **Append to `.eval/summary.md`** following the prior round's entry shape (delta table + new top 3 failure modes + holdout-only signals + next-round action).
8. **Return JSON to the main agent** (see schema in `round-runner-prompt.md`). Keep the prose summary under ~300 words.

## Settled design decisions (15)

1. **Judge grades absolutely** against the issue; opus output is calibration reference, not ground truth. Judge flags opus errors via `opus_flagged_wrong`.
2. **Round runner sub-agent orchestrates each round end-to-end.** Main agent only sequences rounds and inspects round-runner return values. Main agent does NOT draft SKILL.md diffs, call dispatch-prompt agents, or run the judge directly.
3. **Train + holdout split** — see `templates/corpus.md`.
4. **k=3 haiku, k=1 opus** per issue per round. Consistency is a rubric dimension.
5. **12-dimension rubric** — see `templates/judge-prompt.md`. Vector grades; no composite. Verdict correctness is hard gate.
6. **Eval branch** = `iterate-skill-triage` (current). `.eval/round-*/` and `.eval/summary.md` are gitignored. Templates and `PLAN.md` are committed. Commit-per-round (by the round runner, on the eval branch).
7. **Triage-agent dispatch** — `general-purpose` + `model` param, per-issue parallel batches (12 + 12 + 8 + 8), workspace path overridden via dispatch prompt, byte-identical wrapper across rounds. No worktree isolation. Spawned by the round runner, not the main agent.
8. **Round runner drafts SKILL.md diffs directly.** No approval gate (autonomous).
9. **Auto-revert** on hard regressions (verdict correctness, rigid-rules pass→fail, consistency drop). **3 consecutive rollbacks → main agent halts.**
10. **Single judge call per round.** YAML frontmatter + prose body. Judge computes `regression_check` itself. Round runner retries judge once on malformed output, then reports halt.
11. **Main session stays light** because sub-agents absorb per-round detail. Handoff only when main-agent context utilization ≥ 50%. Manual restart by user resumes at the next round.
12. **Round 0 = baseline** (calibration). Spot-check picks at `templates/corpus.md`. After user calibration approval, loop is autonomous until halt or user interrupt. **No round-count cap.**
13. **End deliverable (user-triggered, not automatic):** when the user is satisfied with progress, they tell the main agent to finalize. The main agent then cherry-picks the final SKILL.md state to clean branch `improve/gutenberg-triage-skill`, opens a PR, and writes `.eval/FINAL-REPORT.md`. Visibility during loop: `.eval/summary.md` + `PushNotification` only on halt events.
14. **Train failure modes only** surfaced for round runner to act on. Holdout corroboration as boolean signal (`also_appears_in_holdout`). Round runner **does not read** holdout `triage.md` files during draft-the-diff time. Overfitting alarm in FINAL-REPORT if train ↑ ≥2 grade-levels while holdout ↑ <0.5.
15. **Failure handling:**
    - Triage sub-sub-agent crash → drop run (counts against consistency); no retry.
    - Judge malformed output → round runner retries once with schema reminder; second failure → return `halt_reason: "judge malformed"`.
    - Opus unreliable at round 0 (>50% flagged) → round runner returns warning in JSON; main agent surfaces to user, can choose to drop opus from rubric (haiku-vs-issue only).
    - Opus drift mid-loop (>40% flagged in a round) → return `halt_reason: "opus calibration drift"`.

## Filesystem layout

```
.eval/
  PLAN.md                                (committed — this file)
  templates/                             (committed)
    dispatch-prompt.md                   (frozen during loop)
    judge-prompt.md                      (frozen during loop)
    round-runner-prompt.md               (frozen during loop)
    corpus.md
  round-0-baseline/                      (gitignored)
    haiku/<issue>-run{1,2,3}/triage.md
    opus/<issue>/triage.md
    judge-report.md
    skill-before.md                      (SKILL.md snapshot)
  round-N/                               (gitignored, same shape)
  summary.md                             (gitignored — convenience digest of commit messages, append-only)
  FINAL-REPORT.md                        (committed when the user triggers finalize)
```

## Round 0 cold-start checklist

The first round runner the main agent spawns is for round 0. Round 0's runner:

1. Verifies `gh` is authed, working dir is the gutenberg checkout.
2. Snapshots current SKILL.md to `.eval/round-0-baseline/skill-before.md`.
3. Dispatches all 40 triage agents (per-issue parallel: 4 agents × 10 issues).
4. Collects JSON payloads. Notes any aborts.
5. Dispatches the judge. Parses YAML frontmatter.
6. Returns JSON to main agent that includes aggregates + top 3 failure modes + opus errors + full per-issue grading for `78342` and `78628` (the calibration spot-checks).
7. Main agent then pauses for the user to approve calibration:
   - "looks calibrated, proceed" → main agent enters the autonomous loop (round 1+).
   - "tweak <X>" → user edits `templates/judge-prompt.md`; main agent re-spawns a judge-only sub-agent and re-presents.
   - "stop" → main agent exits.

Round 0 makes NO SKILL.md edit. Round 1 onward edits based on round 0's judge.

## Resumption (post-handoff)

A successor main session restarting this loop should:

1. Read this file (`.eval/PLAN.md`).
2. Read `.eval/templates/` (corpus, dispatch prompt, judge prompt, round-runner prompt).
3. Read `.eval/summary.md` for the round-by-round trend.
4. Read the latest handoff doc (path printed in the restart message).
5. Read `git log iterate-skill-triage --oneline` for the canonical changelog and rollback-counter inference.
6. Read the latest `.eval/round-N/judge-report.md` for current state.
7. Resume the main loop at the next round. No round cap — keep iterating until a halt condition fires or the user interrupts.

Do NOT re-design. The grilling that produced the 15 decisions is settled. Read `.eval/templates/` and resume.
