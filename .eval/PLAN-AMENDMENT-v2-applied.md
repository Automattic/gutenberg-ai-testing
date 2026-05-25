# PLAN amendment v2 — applied (superseded)

**Status:** SUPERSEDED. Retained for forensic reference only. The canonical version of decisions 16–20 (and the amendments to 5, 9, 14) lives in `.eval/PLAN.md`. If this file disagrees with `PLAN.md`, `PLAN.md` wins.

Applied in the commit that introduced the `-applied` suffix on this filename. The integration into `PLAN.md`, the new aggregate keys + `soft_regressions:` block in `templates/judge-prompt.md`, and the template "frozen-since-v2-amendment" stamp all land in that same commit.

## Motivation

After round 10 the four headline metrics the loop watches are saturated (train verdict 21/21, train rigid_rules 21/21, train consistency_3of3 7/7, holdout verdict 9/9). The 12-dimension rubric still grades meaningful headroom (most haiku runs are `good` where opus is `excellent`; image_observations_restated is 10/15; calibration is 19/21). Two things need to change for the loop to keep producing signal:

1. The **scoring surface** must include more of what the judge already grades — otherwise edits that improve `excellent_rate` or `image_observations_restated` are invisible to the round runner.
2. The **corpus** must include shapes the current 10 don't cover — otherwise the same failure-mode taxonomy keeps recurring and the model has effectively memorised the inputs.

These changes are complementary. Doing only (1) measures saturation more precisely. Doing only (2) widens the input set but reads it through the same narrow output lens.

## Amendments to existing decisions

### Decision 5 (rubric) — additive

Keep all 12 dimensions exactly as is. Add the following **aggregate buckets** to the judge's `aggregates` block (per split):

```yaml
aggregates:
  train:
    # existing
    verdict_correctness_haiku: "21/21"
    rigid_rules_compliance_haiku: "21/21"
    consistency_3of3: 7
    consistency_2of3: 0
    consistency_1of3: 0
    consistency_0of3: 0
    # NEW — soft-signal aggregates (observability, not regression triggers)
    confidence_calibration_correct: "19/21"        # over runs where verdict == Valid bug
    image_observations_restated_done: "10/15"      # over runs where issue has images
    injection_handling_done: "N/M"                  # over runs where applicable
    steps_quality_excellent_rate: "0/15"           # over Valid-bug runs
    preconditions_completeness_excellent_rate: "0/15"
    code_findings_quality_excellent_rate: "5/15"
    verdict_reasoning_quality_excellent_rate: "0/21"
```

All denominators are run-level (haiku only; opus excluded from haiku aggregates). `na` runs are excluded from both numerator and denominator.

### Decision 9 (regression) — additive, conservative

Keep all existing **hard** triggers (verdict drop, rigid_rules pass→fail, consistency 3/3 drop ≥2, opus drift). Hard triggers remain the only thing that causes auto-revert.

Add **soft** triggers that do NOT cause revert. They appear in the judge report as `soft_regressions: [...]` and are passed to the round runner's "next action" reasoning. The round runner SHOULD NOT chain a fix to a soft trigger if the immediately-prior round was a hard revert (avoid stacking risk near the ceiling).

Soft triggers fire when any of these drops vs the prior round:

- `image_observations_restated_done` numerator drops by ≥2
- `confidence_calibration_correct` numerator drops by ≥2
- any `excellent_rate` numerator drops by ≥3

Rationale: the judge already produces this signal; widening observability without widening the revert surface is the conservative move. If subsequent rounds show soft triggers correlate well with real regressions, escalate them to hard triggers in a later amendment.

### Decision 14 (holdout firewall) — clarification, unchanged

Holdout still firewalled. Aggregates above apply per-split. Round runner still does not read holdout `triage.md` files. New corpus issues admitted to holdout (decision 16 below) inherit the firewall.

## New decisions (16–19)

### 16. Corpus expansion event — rules

Corpus expansion is **user-triggered, not autonomous**. The round runner never adds or removes issues. The main agent never adds or removes issues mid-loop.

When the user triggers an expansion event:

- **Batch size:** add between 3 and 8 new train issues, and 1–3 new holdout issues, per event.
- **Cap:** total corpus must not exceed 25 issues (≈100 dispatches/round) without a separate cost approval from the user. The current 10 has cost ~40 calls/round; 18 issues will cost ~72/round. Document the projected per-round cost in the expansion commit message.
- **Stratification:** preserve the existing skew (mostly Valid bug + a few Out of scope + a few Insufficient info) unless the user explicitly broadens. New issues do not need to match existing predicted-verdict mix exactly.
- **Re-baseline:** the round immediately following an expansion event uses `regression_check.triggered: false` unconditionally (no prior aggregates are comparable). The round after that resumes normal regression checking against the post-expansion round as baseline. Soft triggers also pause for one round.
- **Rollback counter:** unaffected. Carries over.
- **Commit:** the expansion is committed as `corpus: expand to N issues (M train + K holdout)` on `iterate-skill-triage`, modifying `templates/corpus.md` only. Templates are otherwise still frozen.
- **No mid-loop deletion** of an existing issue. Removing an issue from the corpus invalidates every prior baseline and is therefore done only at finalize, with the rationale recorded in `FINAL-REPORT.md`.

### 17. Candidate shape-gap taxonomy

A candidate is admissible to the corpus only if it covers at least one shape the current corpus does not, or fails the cold-read protocol (decision 18) on ≥1 rubric dimension. Shape-gap categories the current 10 do NOT cover well, in priority order:

| # | Shape | Why interesting | What it stresses |
|---|---|---|---|
| 1 | **Maintainer-flip thread** — verdict changes mid-discussion (e.g., initially declared "intentional" then re-opened as a bug) | Calibration must integrate later evidence over earlier framing | confidence_calibration, verdict_reasoning_quality |
| 2 | **Video-only repro** — no screenshots, only `.mov`/`.mp4`/animated GIF | Skill currently defers; is that always right? | image_observations_restated (`na` handling), verdict_correctness |
| 3 | **Title-vs-body disagreement** — title says "X is broken", body shows X working and Y broken | Skill must read body over title | verdict_correctness, steps_quality |
| 4 | **Long thread** (>50 comments) with multiple competing reproductions | Context-window stress; calibration on multi-party evidence | consistency, verdict_reasoning_quality |
| 5 | **Multi-block / cross-package** — bug spans two block-editor primitives or a block + a server endpoint | Code findings must traverse | code_findings_quality |
| 6 | **Timing / race / performance** with reporter measurements | Calibration on quantitative evidence vs hand-wave | confidence_calibration, code_findings_quality |
| 7 | **Linked PR later reverted** — issue references a fix that was rolled back | Skill must check current state of referenced commits | code_findings_quality |
| 8 | **Truly empty `_No response_` body** with a clear title | Insufficient-info edge case | verdict_correctness |
| 9 | **Non-English reporter content** (Spanish, Japanese, Portuguese — common in gutenberg) | Image content + maintainer translations must be integrated | image_observations_restated, verdict_reasoning_quality |
| 10 | **Paste-bin / pastebin / gist link** as the primary repro vehicle (vs inline content) | Skill currently doesn't fetch these; what does it do? | rigid_rules_compliance, code_findings_quality |
| 11 | **Reproduction depends on a specific plugin** (Yoast, WooCommerce blocks, Jetpack) | Out of scope vs Valid stratification under plugin dependency | verdict_correctness, preconditions_completeness |
| 12 | **Closed-as-WONTFIX with active comments** | State gate + maintainer-intentional combined | verdict_correctness, rigid_rules_compliance |

The current 10 cover shapes: closed-as-duplicate (78628), contested-screenshot-grid (78625), maintainer-intentional (78533/76568/78238), image-content-narration (76568/78342/78533), BEGIN/END AI injection (77678), CSS cascade hypothesizing (77830 holdout), Table interaction (77939 holdout), submenu a11y (78355 holdout). Shape categories 1–12 above are mostly orthogonal to this list.

### 18. Candidate cold-read protocol

To rank candidates before admitting them:

1. **Prefilter** with `.eval/scripts/prefilter-candidates.sh` — pulls 100–200 open + recently-closed gutenberg issues via `gh`, scores them on shape signals (comment count, image/video attachments, body length, label set, closed state + duplicate marker, etc.), and writes `.eval/candidates/prefilter.tsv` ranked by an additive shape-coverage heuristic.

2. **Cold-read** the top 20–30 candidates with `.eval/scripts/score-candidates.sh`:
   - Dispatches 3 haiku + 1 opus per candidate via `.eval/templates/cold-read-prompt.md` (byte-identical to dispatch-prompt.md plus a structured return).
   - Workspace under `.eval/candidates/<num>-run{1,2,3}/triage.md` and `.eval/candidates/<num>-opus/triage.md`.
   - Total token cost ~100 dispatches; comparable to ~2.5 full rounds.

3. **Headroom score** computed per candidate from the 12-dimension grades:
   - +2 for each haiku run where verdict_correctness is `incorrect` (verdict ambiguity is a strong learning signal — but only admit if it's *resolvable*, not pathological).
   - +1 for each haiku run with confidence_calibration `incorrect` (when applicable).
   - +1 for each haiku run with image_observations_restated `not-done` (when applicable).
   - +1 for each haiku run with rigid_rules_compliance `fail`.
   - +0.5 for each haiku run that hits `good` or below on a dimension where opus hit `excellent`.
   - Penalty: -3 if any haiku run is `aborted` (operational failure ≠ headroom).
   - Penalty: -5 if cross-run verdict agreement is 0/3 with no defensible majority (pathological — corpus needs a stable ground truth).

4. **User curation:** the user reviews the top 10 by headroom score, picks 3–8 to admit. The script does not auto-admit.

5. **Ground-truth note:** the user records each admitted issue's predicted verdict in `templates/corpus.md` (and any corpus-tolerated alternatives, mirroring 78625's "Valid or Insufficient"). The judge enforces verdicts against this; not against the cold-read result.

### 19. Simplification edits are a first-class round outcome

After 10 rounds the loop has only ever ADDED to `SKILL.md` — current size is 229 lines, up from the round-0 baseline. Some accreted rules may be redundant, over-specific, or generalisable. Three explicit edit shapes are now allowed:

| Edit shape | What it does | Risk profile | Commit prefix |
|---|---|---|---|
| **Additive** | Adds a new rule, audit, forbidden-pattern, or example | Standard (rounds 1–10) | `round-N: <subject>` |
| **Subtractive** | Removes a rule the loop now believes is redundant or over-firing | Higher per-line because the model may have been relying on it | `round-N: SIMPLIFY: remove <thing>` |
| **Generalising** | Replaces N specific rules with a smaller M (M<N) more general rule that covers the same cases | Higher than additive, lower than pure subtractive | `round-N: SIMPLIFY: generalise <thing>` |

A simplification edit must:

1. **Touch `SKILL.md` only.** No `references/` changes paired with a simplification — too hard to attribute outcomes. (`references/` edits are still allowed in additive rounds.)
2. **Net-reduce line count.** Verifiable via `wc -l`. The round-runner records `delta_lines: -N` in the round summary.
3. **Explicitly name what was removed or generalised** in the commit body. Forensic clarity for future maintainers and for the rollback diagnostic.
4. **Stand alone.** A simplification round may NOT be paired with an additive edit in the same commit. If two changes are needed, run two rounds.

Pass criteria for simplification edits are **stricter** than additive edits:

- All existing hard triggers must pass (verdict, rigid_rules, consistency — unchanged).
- **Zero tolerance on soft signals.** None of `image_observations_restated_done`, `confidence_calibration_correct`, or any `excellent_rate` numerator may drop AT ALL vs the prior round. Additive edits tolerate small soft regressions (decision 9 thresholds); simplification edits do not. Rationale: the explicit trade is "less skill text in exchange for the same quality" — if quality drops by any measurable amount, the trade is bad.
- Standard auto-revert on failure. Reverted simplifications count toward the 3-consecutive-rollback halt counter exactly like reverted additive edits.

When the round-runner SHOULD consider a simplification:

- **After ≥3 consecutive rounds** where no metric (hard or soft) moves more than noise. Saturation is the loop's signal that the current rule set is mature and may be over-prescribed.
- **When a judge-surfaced failure mode looks like over-firing** of an existing rule (e.g., a round-5-style failure where a Step-4 trigger was applied too broadly). Removing or generalising the over-firing rule is preferred over piling another rule on top of it.
- **When `SKILL.md` has grown by ≥15 lines** since the most-recent successful simplification round (or since round 0 if no simplification has succeeded yet). Round 0 baseline = 229 lines; the round-runner trips this heuristic at 244 lines. The line counter resets on every accepted simplification.

When the round-runner should NOT attempt a simplification:

- Within the same round as a corpus-expansion event's re-baseline (decision 16). Wait at least 2 normal rounds before simplifying against the new baseline.
- When the rollback counter is ≥1 (a fresh additive revert means the model is brittle near the current edit; pulling a load-bearing rule will likely also revert).
- When the candidate removal targets an audit added in the last 2 rounds (insufficient evidence that it's actually redundant).

The round-runner records in `summary.md`:

- `skill_lines_after_round: 231` (or whatever)
- For simplification rounds: `delta_lines: -7`, `removed: "round-5 Step-4 maintainer-intentional bullet"`, `generalised: <description>`.

This gives the loop a running ledger of the skill's size and a way to detect "accidentally one-way-additive" drift in future eval sessions.

### 20. When to trigger a corpus expansion event

This is a heuristic, not a hard rule:

- After **3 consecutive rounds** where no metric (hard or soft) moves more than noise.
- After a **hard regression revert** that targets a failure mode for which no train issue exists (i.e., the loop can't measurably retry the same shape).
- When the user observes a class of real-world triage failures **not represented** in the current corpus.

Do NOT expand:

- Mid-revert sequence (rollback counter ≥1).
- Within 3 rounds of a prior expansion event (let the new shape work through the loop first).
- To "look like progress" when the loop is genuinely at ceiling. Finalize instead.

## Migration plan (when this amendment is accepted)

1. User says "accept v2 amendment" (or similar).
2. Main agent (or user) folds amendments into `PLAN.md`:
   - Edit decision 5 to point to the new aggregates section.
   - Edit decision 9 to add the `soft_regressions` block.
   - Append decisions 16–20.
3. Edit `templates/judge-prompt.md`:
   - Add the new aggregate keys under `aggregates.train` and `aggregates.holdout`.
   - Add a top-level `soft_regressions:` list to the YAML.
   - Update the "What to return" final-message block to also print `soft_regressions` count.
4. Edit `templates/round-runner-prompt.md` (when this gets re-introduced) to parse `soft_regressions` and feed it into the next-action reasoning.
5. Bump templates from "frozen" to "frozen-since-v2-amendment". Next handoff carries the version stamp.
6. This file is renamed `PLAN-AMENDMENT-v2-applied.md` and a `superseded:` line is added at the top.

## What the user does next, in order

1. Review this file. Push back on any of decisions 16–20.
2. If accepting in principle: run `.eval/scripts/prefilter-candidates.sh` to produce a ranked list. (Takes ~30 seconds + ~30 `gh` calls.)
3. Glance at the top 20–30 candidates in `.eval/candidates/prefilter.tsv` and sanity-check the shapes.
4. Run `.eval/scripts/score-candidates.sh` to cold-read the top 20–30. (Costs ~80–120 dispatches; comparable to 2–3 full rounds.)
5. Pick 3–8 train + 1–3 holdout admits from the headroom-ranked output.
6. Apply the migration plan above; resume the loop at round 11 against the new criteria.
