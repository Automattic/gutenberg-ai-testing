# FINAL REPORT — gutenberg-triage skill eval loop

**Branch:** `iterate-skill-triage` (eval scaffolding, gitignored artifacts) → `improve/gutenberg-triage-skill` (clean PR).
**Final SKILL.md commit (clean):** `improve/gutenberg-triage-skill@21e2816e38 gutenberg-triage: harden Step-4/Step-5 rules from a 14-round haiku eval loop`.
**Eval-branch HEAD at finalize:** `e1785dbfdf round-14: add Step-4 linked-PR-draft/roadmap-status low-confidence trigger`.
**Corpus:** 17 issues (12 train + 5 holdout) drawn from `WordPress/gutenberg`. See `.eval/templates/corpus.md`.
**Rounds run:** 0–14 (15 total; rounds 5 + 9 auto-reverted; rounds 1–4, 6–8, 10–14 landed cleanly).
**Total dispatches:** ~840 triage runs + 15 opus judge calls.

## What this loop did

Each round followed the same shape:

1. Read the prior round's `judge-report.md` and pick the top-ranked train failure mode.
2. Apply the smallest viable edit to `.claude/skills/gutenberg-triage/SKILL.md` targeting that mode.
3. Dispatch 51 haiku triage runs (3 per issue) + 17 opus calibration runs.
4. Dispatch one opus judge that grades all 68 runs against a 13-dimension rubric (12 dimensions plus the amendment-v3 `haiku_confidence_agreement`), computes a hard-regression check, and emits an observability-only `soft_regressions` list.
5. Auto-revert the round commit on any hard regression. Keep on soft.

The full per-round trajectory is in `.eval/summary.md`. PLAN decisions (1–21) — including the amendment-v2 corpus expansion (round 11) and amendment-v3 cross-run agreement metrics (round 13) — are documented in `.eval/PLAN.md`. The harness-level bg-session edit-tool blocker that surfaced at round 14 is also documented in PLAN.md so a future session can patch SKILL.md via `Bash`+`python3` without pausing.

## Final state (round 14, accepted)

| Metric | Train (36 haiku runs over 12 issues) | Holdout (15 haiku runs over 5 issues) |
| --- | --- | --- |
| verdict_correctness | **36/36** | **15/15** |
| rigid_rules_compliance | **36/36** | **15/15** |
| consistency_3of3 (verdict) | **12/12** | **5/5** |
| confidence_calibration_correct | 26/33 | 14/15 |
| image_observations_restated_done | 8/15 | 6/9 |
| injection_handling_done | 0/3 | 0/0 |
| confidence_consistency_3of3 (amendment v3) | 7 | 4 |
| full_agreement_3of3 (amendment v3) | 8 | 4 |
| opus_flagged_wrong | 0/17 | — |

`verdict_correctness`, `rigid_rules_compliance`, and `consistency_3of3 (verdict)` are at full ceiling on both splits. Verdict agreement across the three haiku runs is unanimous on every issue — the model now produces the same triage call whether it sees the issue once or three times, on issues it has never been calibrated against (holdout).

## Where the edits landed

The accepted skill diff (`improve/gutenberg-triage-skill`) is +45/−4 vs the prior SKILL.md on `trunk`, concentrated in Steps 4–5. The five durable mechanisms:

1. **Step 4 image-restatement rule** with worked forbidden patterns (`image-1.png saved`, `see image-N.png`, count-only narratives, etc.). Replaces the prior single-sentence directive with an enumerated check.
2. **Step 4 low-confidence trigger list** broadened to single-trigger downgrades on theme/version/repro/comment-disagreement signals. The round-14 linked-PR-draft / roadmap bullet was added here.
3. **Step 4 Reserve-high paragraph** spelling out that maintainer "intentional / by-design" framing downgrades confidence to `low` but does NOT flip the verdict to `Out of scope`. (Anti-pattern caught in round 6 and made explicit.)
4. **Step 5 canonical seven section headings** enumerated inline. `/gutenberg-repro` parses these exact names. (Round 1.)
5. **Step 5 pre-write audit cluster** — four audits that fire on the planned content before the file is rendered:
   - **Image audit** (round 4 / 8): rewrites any filename-pointer text into descriptive prose.
   - **Confidence audit** (round 7 / 11 / 12): downgrades `high` → `low` when comments OR linked-ref bodies contain maintainer-intentional / roadmap / cascade-pattern tokens.
   - **Anti-hypothesis audit** (round 10): rewrites root-cause-shaped statements ("the root cause is", "appears to be a timing issue", "cascade conflict", "paint timing") into factual observations. Cause-and-effect synthesis is `/gutenberg-fix`'s territory.
   - **Verdict-routing audit** (round 13): on open `[Type] Bug` issues, blocks the `Out of scope` exit when the OOS justification cites maintainer framing tokens; rewrites as `Valid bug candidate / low`.

## Reverted rounds (cautionary tale)

- **Round 5** — REVERTED. Train `verdict_correctness` dropped 21/21 → 17/21 and consistency dropped 6 → 3. The added bullet over-fired and flipped Valid bug → Out of scope on 76568/78533.
- **Round 9** — REVERTED. Train `rigid_rules_compliance` went pass → fail on 78628 run3 (closed-state gate bypass) and 78238 run3 (root-cause hypothesis). A worked image-narration example in `references/triage-template.md` caused subtle anti-pattern bleed-through. Lesson: worked examples in the references/ tree are durably risky for haiku — they leak into outputs as if they were rules.

The hard-regression rule set (PLAN decision 9) caught both, returned SKILL.md to the prior accepted state, and the loop continued without compounding damage. The rollback counter never reached 3/3.

## Known limitations (carried into the final state)

These are documented for downstream consumers of the skill. None of them are bugs in the SKILL itself — they are model-capability bounds at haiku scale.

1. **76031 — irreducible confidence over-attribution.** The reporter writes a confident "Root Cause" + "Suggested Solutions" body, and the Depth-2 grep confirms the named symbols (`preloadStyles`, `applyStyles`, `updateStylesWithSCS`). Maintainer @luisherranz adds the issue to a roadmap discussion (#52904). Haiku reads the structured body + verified mechanism and ignores the roadmap signal. Four mechanism shifts targeted this issue: Step-5 confidence audit (round 7), cascade-pattern tokens (round 11), linked-ref scope + roadmap tokens (round 12), Step-4 linked-PR-draft trigger (round 14). All four failed. Run1 of round 14 even cites the rule and rejects it ("No draft PR or imminent fix is linked, so confidence remains high"). The body framing outweighs every rule shape tried at this corpus size for haiku.
2. **Image observations on plain-screenshot issues** (76568, 78628, 78625). Haiku acknowledges that screenshots exist but doesn't always describe their content (the rule asks for the latter). The audit catches filename-pointer phrasing reliably but doesn't force content-level description when none was attempted.
3. **77678 injection-handling restatement.** Round-14 saw 0/3 haiku runs surface the BEGIN/END AI-generated-text markers in `Notes`. Round 13 had 1/3 done. Verdicts and rigid-rules are unaffected (the untrusted-input handling is still working — the markers are just not being named in the report). Lowering transparency, not correctness.

## Cost and time

15 rounds × 68 triage dispatches + 1 judge call ≈ 1035 sub-agent dispatches plus context-management work in the main session. The loop converged on hard-metric ceiling at round 11 (the corpus-expansion re-baseline) and stayed there through rounds 12–14, with rounds 12–14 chasing soft signals and one persistent confidence calibration miss (76031). Net leverage of rounds 12–14 over round 11: +1 `consistency_3of3` on each split (full ceiling reached), and a documented anti-pattern (Step-4 natural-language disjunction is read as a conjunction by haiku).

## Recommendation

- **Ship `improve/gutenberg-triage-skill`** as the canonical SKILL.md going forward.
- **Do not add more rules** targeting 76031 without a corpus-coverage shift. The current rule shape (natural-language token list inside Step-4 or Step-5) has been exhausted across four mechanism types. A capable rule would need to inspect linked-PR state programmatically (e.g., a `gh pr view <ref> --json state` call inside the skill workflow), but that's a different design from the text-and-grep-only contract this skill operates under.
- **Watch the 77678 injection-handling drift.** If it widens to other injection-shaped issues, surface the regression and consider promoting the marker-restatement directive to a rigid rule rather than a guidance bullet.
- **Re-grade with a different model in the same harness.** The eval loop is model-agnostic; running rounds 0–N against Claude Sonnet 4.6 or 4.7 would surface a different failure-mode topology and may close the 76031 gap.

End of report.
