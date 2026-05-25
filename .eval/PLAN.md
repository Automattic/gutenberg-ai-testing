# Gutenberg-triage skill improvement loop — PLAN

This file is the contract for an autonomous eval loop that improves `.claude/skills/gutenberg-triage/SKILL.md` so the **haiku** model can reliably produce excellent triage results. It is the kickoff doc for any session (initial or post-handoff) that drives the loop.

## What the loop does each round

For each round N (rounds 0–10):

1. **Dispatch** per-issue parallel batches of subagents:
   - 3 haiku runs of the `gutenberg-triage` skill per train+holdout issue
   - 1 opus run per train+holdout issue
   - All use byte-identical wrapper prompt (`templates/dispatch-prompt.md`), only `model` differs
2. **Judge:** single opus call (`templates/judge-prompt.md`) reads all triage.md + issue contexts, produces a YAML-frontmatter + prose report
3. **Parent (this session):**
   - Parse judge's YAML frontmatter
   - If `regression_check.triggered: true` AND not round 0: `git revert` the previous round's SKILL.md edit, commit as `round-N: REVERTED — <reasons>`, increment rollback counter
   - Else: read the prose body, draft a SKILL.md edit targeting the top train failure mode (prioritizing modes with `also_appears_in_holdout: true`), commit as `round-N: <subject>`
   - Append a one-line summary to `.eval/summary.md`
   - If 3 consecutive rollbacks → halt, write final report
   - If round 10 done → cherry-pick to clean branch, open PR, write final report
   - Else proceed to round N+1
4. **Handoff:** at any clean checkpoint (between rounds, after commit), if context utilization ≥ 30%, invoke the `handoff` skill and exit cleanly with a restart command for the user

## Settled design decisions (15)

1. **Judge grades absolutely** against the issue; opus output is calibration reference, not ground truth. Judge flags opus errors via `opus_flagged_wrong`.
2. **Parent Claude orchestrates** end-to-end. No editor subagent. Autonomous within a session.
3. **Train + holdout split** — see `templates/corpus.md`.
4. **k=3 haiku, k=1 opus** per issue per round. Consistency is a rubric dimension.
5. **12-dimension rubric** — see `templates/judge-prompt.md`. Vector grades; no composite. Verdict correctness is hard gate.
6. **Eval branch** = `iterate-skill-triage` (current). `.eval/round-*/` and `.eval/summary.md` are gitignored. Templates and `PLAN.md` are committed. Commit-per-round.
7. **Subagent dispatch** — `general-purpose` + `model` param, per-issue parallel batches (4 agents at a time), workspace path overridden via dispatch prompt, `bypassPermissions`, byte-identical wrapper across rounds. No worktree isolation.
8. **Parent drafts SKILL.md diffs directly.** No approval gate (autonomous).
9. **Auto-revert** on hard regressions (verdict correctness, rigid-rules pass→fail, consistency drop). **3 consecutive rollbacks → stop.**
10. **Single judge call per round.** YAML frontmatter + prose body. Judge computes `regression_check` itself.
11. **Clean-checkpoint handoff** at ≥30% context. Manual restart by user.
12. **Round 0 = baseline** (not counted in 10). Spot-check picks at `templates/corpus.md`. After user calibration approval, loop is autonomous until handoff/completion.
13. **End deliverable:** cherry-pick final SKILL.md to clean branch `improve/gutenberg-triage-skill`, open PR. Write `.eval/FINAL-REPORT.md`. Visibility during loop: `.eval/summary.md` + `PushNotification` only on stop events.
14. **Train failure modes only** surfaced for parent to act on. Holdout corroboration as boolean signal (`also_appears_in_holdout`). Parent **does not read** holdout `triage.md` files during draft-the-diff time. Overfitting alarm in FINAL-REPORT if train ↑ ≥2 grade-levels while holdout ↑ <0.5.
15. **Failure handling:**
    - Subagent crash → drop run (counts against consistency); no retry
    - Judge malformed output → one retry with schema reminder, then halt
    - Opus unreliable at round 0 (>50% flagged) → warn user, drop opus from rubric (haiku-vs-issue only)
    - Opus drift mid-loop (>40% flagged in a round) → halt + handoff with "calibration drift" note

## Filesystem layout

```
.eval/
  PLAN.md                                (committed — this file)
  templates/                             (committed)
    dispatch-prompt.md
    judge-prompt.md
    corpus.md
  round-0-baseline/                      (gitignored)
    haiku/<issue>-run{1,2,3}/triage.md
    opus/<issue>/triage.md
    judge-report.md
    skill-before.md                      (SKILL.md snapshot)
  round-N/                               (gitignored, same shape)
  summary.md                             (gitignored — convenience digest of commit messages)
  FINAL-REPORT.md                        (committed at end)
```

## Round 0 cold-start checklist

1. Verify `gh` is authed, working dir is gutenberg checkout.
2. Snapshot current SKILL.md to `.eval/round-0-baseline/skill-before.md`.
3. Dispatch subagents for all 10 issues (per-issue parallel: 4 agents × 10 = 40 total).
4. Collect JSON payloads. Note any aborts.
5. Dispatch judge. Parse YAML frontmatter.
6. Show user: aggregates + top 3 failure modes + opus errors + full per-issue grading for `78342` and `78628`.
7. Wait for user response:
   - "looks calibrated, proceed" → enter autonomous mode
   - "tweak <X>" → edit `templates/judge-prompt.md`, re-dispatch judge only, re-present
   - "stop" → exit
8. Round 0 makes NO SKILL.md edit. Round 1 onward edits based on round 0's judge.

## Resumption (post-handoff)

A successor session restarting this loop should:

1. Read this file (`.eval/PLAN.md`).
2. Read `.eval/templates/` (corpus, dispatch prompt, judge prompt).
3. Read `.eval/summary.md` for the round-by-round trend.
4. Read the latest handoff doc (path printed in the restart message).
5. Read `git log iterate-skill-triage --oneline` for the canonical changelog.
6. Read the latest `.eval/round-N/judge-report.md` for current state.
7. Pick up from the next round (or completion step if round 10 already done).

Do NOT re-design. The grilling that produced the 15 decisions is settled. Read `.eval/templates/` and resume.
