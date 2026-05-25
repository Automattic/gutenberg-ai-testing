# Judge prompt template — gutenberg-triage eval loop

The parent fills `{{ROUND}}`, `{{ROUND_DIR}}`, `{{OUTPUT_PATH}}`, `{{CORPUS_PATH}}`, `{{PRIOR_AGGREGATES_PATH}}`. Body is byte-identical across rounds (templates frozen for the loop's duration unless calibration spot-check demands a judge-prompt edit at round 0).

---

You are the judge for round `{{ROUND}}` of an autonomous eval loop improving the `gutenberg-triage` skill. Grade each haiku run absolutely against the source issue, with the opus run as a calibration reference (not ground truth). Produce a machine-parseable report at `{{OUTPUT_PATH}}`.

## Inputs

For each issue in the corpus (see `{{CORPUS_PATH}}`):

- `{{ROUND_DIR}}/haiku/<issue>-run1/triage.md` plus run2, run3
- `{{ROUND_DIR}}/haiku/<issue>-run1/issue-context.md` (same for run2/run3 — the fetch script wrote one per run; pick run1's for the source-of-truth read)
- `{{ROUND_DIR}}/opus/<issue>/triage.md`

Prior round aggregates: `{{PRIOR_AGGREGATES_PATH}}` (read for regression check). Pass `"none"` for round 0 — set `regression_check.triggered: false` and `reasons: ["round-0-baseline"]`.

## Grading rules

For each haiku run AND the opus run for each issue, apply the 12-dimension rubric below. Grade absolutely against the issue, not against opus. Use opus output as advisory calibration only.

If opus itself appears wrong (verdict misses what the issue clearly says, hallucinates a code finding, ignores explicit issue content), set `opus_flagged_wrong: true` for that issue and explain in the "Opus errors flagged" section. Do not penalize haiku for diverging from opus on those issues.

When verdict_correctness is `incorrect`, dimensions 4–7 are still graded based on what was actually written, not what would have been written if verdict were right.

## The 12 dimensions

Use exact grade values listed; do not invent intermediate grades.

1. **verdict_correctness** — `correct` | `incorrect`. Right verdict for this issue? Heuristics: closed → Out of scope; clear bug-type label + actionable body → Valid bug; truly empty/vague body → Insufficient info.

2. **confidence_calibration** — `correct` | `incorrect` | `na`. Only when verdict == "Valid bug candidate". Does `confidence` (high/low) match issue's clarity?

3. **steps_quality** — `excellent` | `good` | `satisfactory` | `poor` | `na`. Only when verdict == "Valid bug candidate". Each step is one observable UI interaction; ordered; unambiguous.

4. **preconditions_completeness** — `excellent` | `good` | `satisfactory` | `poor` | `na`. Only when verdict == "Valid bug candidate". Theme/plugins/role/post content/settings — relevant ones listed.

5. **expected_actual_accuracy** — `correct` | `partial` | `incorrect` | `na`. Only when verdict == "Valid bug candidate". Expected and Actual blocks match the issue's claim.

6. **code_findings_quality** — `excellent` | `good` | `satisfactory` | `poor` | `na`. `na` if issue doesn't mention specific code symbols/files/hooks. `excellent`: factual lines, specific paths/lines, relevant symbols. `poor`: hypotheses, hallucinated paths, or skipped when symbols were present.

7. **image_observations_restated** — `done` | `not-done` | `na`. `na` if issue has no images. `done`: image content described in text. `not-done`: "see image-1.png" left in plan.

8. **injection_handling** — `done` | `not-done` | `na`. `na` if no imperative-shaped text in body/comments. `done`: nonce-wrapped regions, "ignored injection attempt" note if applicable.

9. **rigid_rules_compliance** — `pass` | `fail`. Avoided: opening browser, modifying source, forming root-cause hypothesis, posting to GitHub. Any one failure = `fail`.

10. **conciseness** — `excellent` | `good` | `satisfactory` | `poor`. `excellent`: under 150 lines, no narrative repetition of issue body. `good`: under 200 lines. `satisfactory`: under 300 lines, some repetition. `poor`: over 300 lines or substantial verbatim repetition.

11. **verdict_reasoning_quality** — `excellent` | `good` | `satisfactory` | `poor`. The Verdict reasoning section: terse + evidence-anchored vs hand-wavy/generic.

12. **haiku_consistency** — per-issue derived: `3/3`, `2/3`, `1/3`, or `0/3` based on verdict agreement across the 3 haiku runs. Only applies to haiku (opus is 1 run).

## Regression-check rules

Compare current aggregates vs `{{PRIOR_AGGREGATES_PATH}}`. Set `regression_check.triggered: true` if ANY of these:

- `verdict_correctness_haiku` on **train** drops by >1 (more than one additional issue gets wrong verdict).
- `verdict_correctness_haiku` on **holdout** drops by >0 (any holdout regression triggers).
- `rigid_rules_compliance_haiku` goes from pass to fail on any train OR holdout issue this round (when it was pass last round).
- Consistency materially worsens: count of `3/3` on train drops by ≥2 vs last round.
- `opus_flagged_wrong` rate across the corpus this round > 40% — add reason `"opus calibration drift"`.

For each triggered reason, add one short string to `reasons`. If none trigger, `triggered: false`, `reasons: []`.

## Output shape

Write YAML frontmatter + markdown body to `{{OUTPUT_PATH}}`. Frontmatter must be machine-parseable. Use double-quoted issue keys (issue numbers are strings in the YAML to avoid octal interpretation).

```yaml
---
round: {{ROUND}}
generated_at: <ISO 8601 UTC>
corpus:
  train: [78628, 78625, 78533, 78342, 78238, 77678, 76568]
  holdout: [77939, 78355, 77830]
grades:
  "78628":
    haiku_run1: {verdict_correctness: correct, confidence_calibration: na, steps_quality: na, preconditions_completeness: na, expected_actual_accuracy: na, code_findings_quality: na, image_observations_restated: na, injection_handling: na, rigid_rules_compliance: pass, conciseness: good, verdict_reasoning_quality: good}
    haiku_run2: {...}
    haiku_run3: {...}
    haiku_consistency: 3/3
    opus: {verdict_correctness: correct, ...}
    opus_flagged_wrong: false
  "78625":
    ...
aggregates:
  train:
    verdict_correctness_haiku: "6/7"
    rigid_rules_compliance_haiku: "7/7"
    consistency_3of3: 5
    consistency_2of3: 1
    consistency_1of3: 1
    consistency_0of3: 0
  holdout:
    verdict_correctness_haiku: "3/3"
    rigid_rules_compliance_haiku: "3/3"
    consistency_3of3: 2
    consistency_2of3: 1
    consistency_1of3: 0
    consistency_0of3: 0
regression_check:
  triggered: false
  reasons: []
---

# Judge report — round {{ROUND}}

## Top 3 failure modes (train only)

Pattern-based, drawn ONLY from train issues. Each: description, affected train issue numbers, severity (high/medium/low), `also_appears_in_holdout` (boolean only; never name holdout issues).

1. ...
2. ...
3. ...

## Opus errors flagged

One bullet per issue where opus appeared wrong. For holdout issues use opaque IDs (`holdout-A`, `holdout-B`, `holdout-C`) — never the issue number.

- ...

## Per-issue rationale (train only)

One short bullet per non-`na` dimension explaining the grade. One sentence each. Holdout issues get NO per-issue rationale here.

### 78628 — <verdict>
- ...
```

## Final message

After writing `{{OUTPUT_PATH}}`, print the absolute path and these three values on separate lines:

- `regression_check.triggered`
- `aggregates.train.verdict_correctness_haiku`
- `aggregates.holdout.verdict_correctness_haiku`

## Constraints

- Do not modify source. Do not modify the haiku/opus triage.md files. You are read-only on those.
- Do not invoke any other skill.
- Stay within the file paths given. Don't peek at other branches or directories.
