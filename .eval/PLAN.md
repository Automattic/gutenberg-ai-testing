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

## Settled design decisions (21)

Decisions 1–15 are the original kickoff contract. Decisions 16–20 were added by amendment v2 (commit `5f9f985d23` proposal, applied in the commit that introduces this section heading). Decision 21 was added by amendment v3 (applied in the commit `eval: apply PLAN amendment v3`). Amendment v2's full prose is preserved at `.eval/PLAN-AMENDMENT-v2-applied.md` for forensic reference; the canonical version is here.

1. **Judge grades absolutely** against the issue; opus output is calibration reference, not ground truth. Judge flags opus errors via `opus_flagged_wrong`.
2. **Round runner sub-agent orchestrates each round end-to-end.** Main agent only sequences rounds and inspects round-runner return values. Main agent does NOT draft SKILL.md diffs, call dispatch-prompt agents, or run the judge directly. *(This decision is overridden in practice: sub-agents cannot spawn sub-agents in the current runtime, so rounds 6–10 ran inline as the main agent. See the most recent handoff doc.)*
3. **Train + holdout split** — see `templates/corpus.md`.
4. **k=3 haiku, k=1 opus** per issue per round. Consistency is a rubric dimension.
5. **12-dimension rubric** — see `templates/judge-prompt.md`. Vector grades; no composite. Verdict correctness is hard gate. **Amended v2:** `templates/judge-prompt.md` also emits soft-signal aggregates (`image_observations_restated_done`, `confidence_calibration_correct`, `injection_handling_done`, and `excellent_rate` for steps_quality / preconditions_completeness / code_findings_quality / verdict_reasoning_quality). All denominators are haiku-only run-level; `na` runs excluded. Soft aggregates are observability, not regression triggers (see decision 9). **Amended v3:** the judge also emits `haiku_confidence_agreement` per Valid-bug issue (`3/3` | `2/3` | `1/3` | `0/3` | `na` — `na` when fewer than 3 runs land on Valid-bug), and the corresponding aggregates `confidence_consistency_3of3` (count of issues whose three haiku runs share the same `confidence` value) and `full_agreement_3of3` (count of issues where verdict AND confidence-when-applicable AND rigid_rules_compliance all match across the three haiku runs). Both new aggregates are soft signals only (decision 9).
6. **Eval branch** = `iterate-skill-triage` (current). `.eval/round-*/` and `.eval/summary.md` are gitignored. Templates and `PLAN.md` are committed. Commit-per-round (by the round runner, on the eval branch).
7. **Triage-agent dispatch** — `general-purpose` + `model` param, per-issue parallel batches (sized to corpus N: 12 + 12 + 8 + 8 at N=10, 12 × 5 + 8 at N=17), workspace path overridden via dispatch prompt, byte-identical wrapper across rounds. No worktree isolation. Spawned by the round runner, not the main agent (subject to the runtime caveat under decision 2).
8. **Round runner drafts SKILL.md diffs directly.** No approval gate (autonomous).
9. **Auto-revert** on hard regressions (verdict correctness, rigid-rules pass→fail, consistency drop). **3 consecutive rollbacks → main agent halts.** **Amended v2:** judge also emits a `soft_regressions: [...]` list (no auto-revert). Soft triggers fire on any of: `image_observations_restated_done` numerator drops ≥2 vs prior round, `confidence_calibration_correct` numerator drops ≥2, or any `excellent_rate` numerator drops ≥3. The round runner reads `soft_regressions` and uses it to inform the next-round action; it must NOT chain a fix to a soft trigger if the immediately-prior round was a hard revert (avoid stacking risk near the ceiling). **Amended v3:** a `confidence_consistency_3of3` drop of ≥2 vs the prior round also fires a soft trigger. `full_agreement_3of3` is observability only (no soft trigger) — it would double-count with the verdict-consistency hard rule and the confidence-consistency soft rule.
10. **Single judge call per round.** YAML frontmatter + prose body. Judge computes `regression_check` itself. Round runner retries judge once on malformed output, then reports halt.
11. **Main session stays light** because sub-agents absorb per-round detail. Handoff only when main-agent context utilization ≥ 50%. Manual restart by user resumes at the next round.
12. **Round 0 = baseline** (calibration). Spot-check picks at `templates/corpus.md`. After user calibration approval, loop is autonomous until halt or user interrupt. **No round-count cap.**
13. **End deliverable (user-triggered, not automatic):** when the user is satisfied with progress, they tell the main agent to finalize. The main agent then cherry-picks the final SKILL.md state to clean branch `improve/gutenberg-triage-skill`, opens a PR, and writes `.eval/FINAL-REPORT.md`. Visibility during loop: `.eval/summary.md` + `PushNotification` only on halt events.
14. **Train failure modes only** surfaced for round runner to act on. Holdout corroboration as boolean signal (`also_appears_in_holdout`). Round runner **does not read** holdout `triage.md` files during draft-the-diff time. Overfitting alarm in FINAL-REPORT if train ↑ ≥2 grade-levels while holdout ↑ <0.5. **Clarified v2:** issues admitted to holdout via corpus-expansion events (decision 16) inherit the same firewall.
15. **Failure handling:**
    - Triage sub-sub-agent crash → drop run (counts against consistency); no retry.
    - Judge malformed output → round runner retries once with schema reminder; second failure → return `halt_reason: "judge malformed"`.
    - Opus unreliable at round 0 (>50% flagged) → round runner returns warning in JSON; main agent surfaces to user, can choose to drop opus from rubric (haiku-vs-issue only).
    - Opus drift mid-loop (>40% flagged in a round) → return `halt_reason: "opus calibration drift"`.
16. **Corpus expansion event — rules.** User-triggered, not autonomous. The round runner never adds or removes issues; the main agent never expands mid-loop. Per event: add 3–8 train + 1–3 holdout. Total corpus ≤ 25 issues without separate user cost approval (current 17 = 68 dispatches/round; 25 would be 100). Preserve existing verdict-mix skew unless explicitly broadened. **Re-baseline:** the round immediately after an expansion uses `regression_check.triggered: false` unconditionally (no prior aggregates comparable); soft triggers (decision 9) also pause for one round. Rollback counter unaffected. Expansion is committed as `corpus: expand to N issues (M train + K holdout)` on `iterate-skill-triage`, touching `templates/corpus.md` only. No mid-loop deletion of an admitted issue; removal only at finalize with rationale in `FINAL-REPORT.md`.
17. **Candidate shape-gap taxonomy.** A candidate is admissible to the corpus only if it covers at least one shape the current corpus does not, or fails the cold-read protocol (decision 18) on ≥1 rubric dimension. The 12 categories (full prose in `.eval/PLAN-AMENDMENT-v2-applied.md` § 17): maintainer-flip thread, video-only repro, title-vs-body disagreement, long thread (>50 comments), multi-block / cross-package, timing/race/performance, linked PR later reverted, truly empty `_No response_` body, non-English content, paste-bin / gist external repro, plugin-dependent, closed-as-WONTFIX with active comments.
18. **Candidate cold-read protocol.** Three-step: (a) prefilter via `.eval/scripts/prefilter-candidates.sh` (~30 sec, 30–200 gh calls); (b) cold-read top 20–30 via `.eval/scripts/score-candidates.sh` using `.eval/templates/cold-read-prompt.md` — 3 haiku + 1 opus per candidate (~100 dispatches; equivalent to ~2.5 rounds); (c) score per the headroom formula in the amendment doc and admit 3–8 by user curation. Cold-read step is OPTIONAL when prefilter shape diversity is already strong (corpus expansion v1 skipped it); the round runner must not autonomously decide to admit based on cold-read alone — admit is always user-curated. Ground-truth verdicts (and corpus-tolerated alternatives, mirroring 78625's "Valid or Insufficient") are recorded in `templates/corpus.md` at admit time.
19. **Simplification edits are a first-class round outcome.** Three edit shapes: **additive** (commit `round-N: <subject>`), **subtractive** (commit `round-N: SIMPLIFY: remove <thing>`), **generalising** (commit `round-N: SIMPLIFY: generalise <thing>`). A simplification edit must: touch `SKILL.md` only; net-reduce line count (verified by `wc -l`, recorded as `delta_lines: -N` in `summary.md`); explicitly name what was removed/generalised in the commit body; stand alone (no additive change in the same commit). Pass criteria are **stricter** than additive edits: all hard triggers must pass AND no soft signal numerator may drop AT ALL (zero tolerance vs the ±2/±3 bands for additive edits). Failures auto-revert and count toward the 3-consecutive-rollback halt. The round runner SHOULD consider a simplification when: (a) ≥3 consecutive flat rounds; (b) judge surfaces a failure mode that looks like over-firing of an existing rule; (c) `SKILL.md` has grown ≥15 lines since the last successful simplification (current baseline 229; trips at 244). The round runner should NOT attempt one within the same round as a corpus-expansion re-baseline (wait ≥2 normal rounds), when rollback counter ≥1, or when the candidate removal targets an audit added in the last 2 rounds. `summary.md` records `skill_lines_after_round: N` per round; on simplification rounds also `delta_lines: -N`, `removed:`, and `generalised:` strings.
20. **When to trigger a corpus expansion event.** Heuristic, not hard rule: after ≥3 consecutive rounds where no metric (hard or soft) moves more than noise; after a hard regression revert that targets a failure mode for which no train issue exists; or when the user observes a class of real-world triage failures not represented in the current corpus. Do NOT expand: mid-revert sequence (rollback counter ≥1); within 3 rounds of a prior expansion event; or to "look like progress" when the loop is genuinely at ceiling (finalize instead).

21. **Cross-run agreement aggregates (observability for non-verdict run-to-run variance).** The 12-dimension rubric grades the 3 haiku runs separately, but dimension 12 (`haiku_consistency`) surfaces cross-run agreement only at the verdict level. Same-verdict-different-confidence shape (e.g., `high`/`high`/`low` on a Valid-bug issue) reads as 3/3 verdict-consistent but is real variance the rubric should expose. Amendment v3 adds:

    - **Per-issue derived field** `haiku_confidence_agreement` — one of `3/3` | `2/3` | `1/3` | `0/3` | `na`. Computed by reading the actual `confidence:` value from each run's `triage.md` YAML frontmatter (the same source the judge already uses to grade `confidence_calibration`). `na` when fewer than 3 haiku runs land on `Valid bug candidate` (the dimension is undefined off that branch).

    - **Aggregate** `confidence_consistency_3of3` — count of issues whose three haiku runs all share the same `confidence` value (i.e., `haiku_confidence_agreement == 3/3`). Goes in both `aggregates.train` and `aggregates.holdout`. Denominator is implicit (count of issues where the field is not `na`).

    - **Aggregate** `full_agreement_3of3` — count of issues where verdict AND confidence (when applicable) AND rigid_rules_compliance all match across the three haiku runs. Tight cross-run reproducibility surface. Goes in both `aggregates.train` and `aggregates.holdout`.

    - **Soft trigger:** a `confidence_consistency_3of3` drop of ≥2 on train vs the prior round emits an entry to `soft_regressions`. `full_agreement_3of3` drops do NOT fire (avoid double-counting with verdict-consistency hard rule + confidence-consistency soft rule).

    - **Re-baseline rule:** the round immediately after a corpus-expansion event (decision 16) sets the soft trigger to "not evaluated" for one round, matching the existing decision-16 re-baseline carve-out. Aggregates themselves are still emitted (observability).

    Steps_quality / code_findings_quality / preconditions / verdict_reasoning variance is intentionally left to the existing `*_excellent_rate` soft signals — a separate per-dimension agreement aggregate would inflate the soft-signal surface without clear regression-action value. If this turns out to be the wrong call, a v4 amendment can add per-dimension agreement.

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

## Operational note: SKILL.md edit-tool blockers (background-session)

When this loop runs as a background-session job, the `Edit`/`Write` tools may refuse SKILL.md edits with "this background session hasn't isolated its changes yet". This is harness-level worktree enforcement, NOT the auto-mode classifier. The eval loop requires commits to land on `iterate-skill-triage` in the shared checkout (per decision 6) so dispatched sub-agents see the updated SKILL.md — entering a worktree splits the source of truth.

The round runner / main agent should NOT pause on this. Apply the SKILL.md edit via `Bash` using `python3` (or a heredoc-fed Python script) to do an in-place string replace. The user has pre-authorized this path; do not surface `needs input:` for it. Always verify the diff with `git diff` before committing. The standing guidance to "surface immediately rather than working around with Bash" applies to the auto-mode classifier, not this enforcement.

## Resumption (post-handoff)

A successor main session restarting this loop should:

1. Read this file (`.eval/PLAN.md`).
2. Read `.eval/templates/` (corpus, dispatch prompt, judge prompt, round-runner prompt).
3. Read `.eval/summary.md` for the round-by-round trend.
4. Read the latest handoff doc (path printed in the restart message).
5. Read `git log iterate-skill-triage --oneline` for the canonical changelog and rollback-counter inference.
6. Read the latest `.eval/round-N/judge-report.md` for current state.
7. Resume the main loop at the next round. No round cap — keep iterating until a halt condition fires or the user interrupts.

Do NOT re-design. The grilling that produced the original 15 decisions is settled, and amendment v2 (decisions 16–20) has been applied. Read `.eval/templates/` and resume.
