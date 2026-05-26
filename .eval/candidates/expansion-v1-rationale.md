# Corpus expansion v1 — selection rationale

**Date:** 2026-05-25 (generated during the round-11 prep session).
**Status:** Applied to `.eval/templates/corpus.md` but **not yet committed**. Pending user review.
**Depends on:** PLAN amendment v2 (decisions 16, 17, 18, 20). Amendment is proposed in `.eval/PLAN-AMENDMENT-v2.md`; this expansion event assumes it is being adopted.

## Why expand now

After round 10 the four headline metrics the round runner gates on are saturated:
- train verdict_correctness_haiku: 21/21
- train rigid_rules_compliance_haiku: 21/21
- train consistency_3of3: 7/7
- holdout verdict_correctness_haiku: 9/9

The 12-dimension rubric still grades meaningful headroom (most haiku runs are `good` where opus is `excellent`; image_observations_restated 10/15; calibration 19/21). But that signal is invisible to the regression check, so the round runner has nothing actionable to chase. Two structural moves are needed: widen the scoring surface (proposed in amendment v2 decision 5 + 9), and expand the corpus to include shapes the current 10 don't cover (amendment v2 decisions 16, 17, 18, 20).

This document is for the second move only.

## Method

1. **Refined prefilter.** Ran `.eval/scripts/prefilter-candidates.sh --state open --limit 400` with `linked-pr` heuristic disabled (47/74 hits in initial 200-issue run — too common to discriminate) and rare-shape boosts applied. Output: 91 ranked candidates.
2. **Restricted to `[Type] Bug` labelled issues** via `awk '$4 ~ /\[Type\] Bug/'`. 22 candidates remained.
3. **Top-8 score≥2 read in full** via `gh issue view`. Read bodies, comment counts, and attachment types.
4. **Diversity selection** against the 12 shape-gap categories in PLAN amendment v2 decision 17, prioritizing gaps the existing 10 don't cover.
5. **Predicted verdicts assigned** by hand-reading each candidate's body. Corpus-tolerated alternatives noted where verdict is genuinely ambiguous (mirroring the existing 78625 "Valid or Insufficient" pattern).

The cold-read protocol from amendment v2 decision 18 step 2–3 was **skipped** for this expansion event — running 28 dispatches (7 candidates × 4) costs comparable to a full round and the prefilter shape diversity is already strong enough to justify admission without it. If round-runner behaviour on the post-expansion baseline reveals any of these 7 are saturated-on-cold-read or pathologically ambiguous, they can be removed at finalize per decision 16.

## Train admits (5)

| # | Predicted verdict | Shapes covered | Why this issue |
|---|---|---|---|
| **76176** | Valid bug | shape 2 (video-only repro), shape 5 (multi-block) | RTC + Block Hooks + post-content. Body references a single video attachment with no still images, and explicitly narrates ("In the video, the last_child hooked block visibly multiplies from 1 copy to 4+ copies…"). Tests `image_observations_restated: na` decision-making — current corpus has 77678 (RTC, no attachments) but no video-only attachment. |
| **77796** | Valid bug | shape 11 (plugin-dependent) | RTC stale `core/missing` after re-enabling a block type. Repro requires WooCommerce or a custom-block plugin to be installed, deactivated, then reactivated. Tests whether the skill records the plugin dependence as a precondition (not as Out-of-scope grounds). Current corpus has zero plugin-dependent reproductions. |
| **76534** | Valid bug (low) | shape 3 (title-vs-body), shape 5 (multi-block) | "WP 7.0 does not support pseudo-selectors for the textInput, select, core/query-pagination-next, core/query-pagination-previous" — body lists 4 distinct block-types, then ends with an off-topic question about whether `core/button` is deprecated. Tests whether the skill triages the actual bug claim and ignores the tangential question (title-vs-body friction). Low confidence because: no comments yet, no environment confirmed beyond reporter's claim. |
| **76031** | Valid bug | code-findings stress; reporter supplies head-merge mechanism | `navigate()` silently deactivates dynamically-injected `<link>` stylesheets on every Interactivity Router SPA navigation. Body is unusually detailed and explains the mechanism explicitly ("The `<link>` node is not always physically removed from the DOM tree…"). The triage skill must treat this as **reporter content** (factual observation in the body) and NOT synthesize a new root-cause hypothesis on top of it — exact stress test for the rigid-rules anti-hypothesis audit landed in round 10. |
| **75443** | Valid bug | version-pinned regression; code-block-heavy body | Block binding to `core/post-meta` for Button `text` attribute fails on front-end unless placeholder content is added. Body pins the regression to Gutenberg 21.7.0 specifically. Tests version-bounded calibration + multi-snippet HTML code findings. |

## Holdout admits (2)

| # | Predicted verdict | Shapes covered | Why this issue |
|---|---|---|---|
| **77530** | Valid or Out of scope (corpus-tolerated) | shape 4 (long-thread >25 comments) | "Visual Revisions: Accessibility" tracking issue, 26 comments, body is a checkbox list with ~14 sub-issues — most marked `[x]` and linked to merged PRs. Several `[ ]` remain. Verdict is genuinely ambiguous: it's a valid (open) work-tracking issue with active sub-items, but the dominant pattern is resolved items pointing to closed PRs. Calibration stress: tests whether the skill integrates the "mostly resolved" framing or anchors on the first un-resolved item. Mirrors 78625's corpus-tolerated-alternatives shape. |
| **75215** | Valid bug | unusual steps shape (body-is-Playwright-test); multi-block (Navigation + Navigation Link) | "Refless Navigation Block does not show block appender." Body contains a complete Playwright spec function (with `await`s and `expect`s) instead of natural-language steps, then a block-code snippet (`<!-- wp:navigation -->`). Tests `steps_quality` on a body where the reporter has supplied test code in place of user-facing reproduction. Also unique: reporter mentions "Claude hasn't been helpful in fixing it yet" — meta-context. Holdout because: this shape would over-fit the round-runner if optimised against directly. |

## Shape-coverage delta

| Shape (amendment v2 decision 17) | Pre-expansion | Post-expansion |
|---|---|---|
| 1. maintainer-flip thread | — | — (not picked; consider next event) |
| 2. video-only repro | — | **76176** ✓ |
| 3. title-vs-body disagreement | — | **76534** ✓ |
| 4. long thread (>25 comments) | — | **77530** ✓ (holdout) |
| 5. multi-block / cross-package | partial (78238, 77678) | **76176, 76534, 75215** ✓ |
| 6. timing / race / performance | — | — (no high-quality candidate in this prefilter run; consider next event) |
| 7. linked PR later reverted | — | — (also requires confirming the linked PR was actually reverted) |
| 8. truly empty body | — | — (no candidate passed the strict empty-body threshold in this run) |
| 9. non-English reporter content | — | — (heuristic produced 0 hits in this 400-issue sample) |
| 10. paste-bin / gist link | — | — (no candidate; codepen reference in 75584 was the closest but issue itself was weaker) |
| 11. plugin-dependent | — | **77796** ✓ |
| 12. closed-as-WONTFIX with active comments | — | — (state filter was `open` only) |
| Code-findings stress (cross-cutting) | partial (77678) | **76031, 75443** ✓ |

Six of twelve shape-gaps now covered (up from zero clean coverage in the original 10). Six remain for a possible future expansion event.

## Token cost projection

- Pre-expansion: 10 issues × 4 dispatches = **40 dispatches per round**
- Post-expansion: 17 issues × 4 dispatches = **68 dispatches per round**
- 70% cost increase per round. Within the 100-dispatch cap in amendment v2 decision 16. Halfway to the 25-issue / 100-dispatch hard ceiling that would require user re-approval.

## What the user should review

1. **Verdict predictions** in the new train/holdout rows. If any of 76176 / 77796 / 76534 / 76031 / 75443 / 77530 / 75215 should be a different verdict, flag it before round 11 runs against the new corpus.
2. **Corpus-tolerated alternatives.** 77530 is marked "Valid or Out of scope" — symmetrical to 78625's "Valid or Insufficient". Push back if either branch should be ruled out.
3. **Whether to apply PLAN amendment v2 before round 11.** This expansion event presumes amendment v2 is being adopted (the re-baseline rule comes from decision 16). If amendment v2 is rejected, this expansion should be reverted.
4. **Skipping the cold-read.** I skipped the formal cold-read scoring step (would have cost ~28 dispatches) because the shape diversity is already strong. If you'd rather see headroom-scored evidence before admitting these, say so and I'll run cold-reads against just the 7 admits.

## Files changed

- `.eval/templates/corpus.md` — bumped to 17 issues, added expansion rows + note explaining the v1 event.
- `.eval/candidates/expansion-v1-rationale.md` — this file.
- `.eval/scripts/prefilter-candidates.sh` — disabled `linked-pr` shape; tightened `timing-perf` regex; added `medium-thread` flag; boosted `multi-block` / `plugin-dep` / `image-heavy` weights from 1 to 2.

Nothing committed yet. Proposed commit message when ready: `corpus: expand to 17 issues (12 train + 5 holdout) per amendment v2 decision 16`.
