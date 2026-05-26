# Eval corpus

17 issues from `WordPress/gutenberg`, split 12 train / 5 holdout. Stratification limited by corpus skew (most are Valid bug candidate, 1 Out of scope, 1 boundary that the corpus tolerates either Valid or Insufficient, 1 boundary that the corpus tolerates either Valid or Out of scope).

The original 10-issue corpus (78628, 78625, 78533, 78342, 78238, 77678, 76568 train + 77939, 78355, 77830 holdout) was authored at round 0. The 7-issue expansion (76176, 77796, 76534, 76031, 75443 train + 77530, 75215 holdout) was added per PLAN amendment v2 decision 16 — selection rationale recorded in `.eval/candidates/expansion-v1-rationale.md`. Until amendment v2 is applied to PLAN.md, the round runner treats these 7 issues as in-corpus but the first round after expansion has `regression_check.triggered: false` unconditionally (re-baseline).

## Train (12)

| # | Predicted verdict | Notes |
|---|---|---|
| 78628 | Out of scope | closed → labeling-gate trips |
| 78625 | Valid or Insufficient | "Columns on WP 7" — vague title |
| 78533 | Valid bug | Post Excerpt regression |
| 78342 | Valid bug | image copy-paste, complex (spot-check pick) |
| 78238 | Valid bug | Cover + YouTube |
| 77678 | Valid bug | RTC malformed input, cross-cutting; injection-shaped BEGIN/END AI block |
| 76568 | Valid bug | writing flow regression; maintainer-intentional ("Yes, this is intentional") |
| 76176 | Valid bug | RTC + Block Hooks + multi-block; video-only attachment; covers shape-gap 2 + 5 |
| 77796 | Valid bug | RTC + plugin-dep (WooCommerce as repro vehicle); covers shape-gap 11 |
| 76534 | Valid bug (low) | multi-block (4 block types) + title-vs-body off-topic Button-deprecation question; covers shape-gap 3 + 5 |
| 76031 | Valid bug | Interactivity Router head-merge; reporter supplies code-mechanism explanation — rigid-rules stress (don't synthesize new hypothesis) |
| 75443 | Valid bug | Version-pinned regression (Gutenberg 21.7.0); block binding; code-block-heavy body |

## Holdout (5)

| # | Predicted verdict | Notes |
|---|---|---|
| 77939 | Valid bug | Table rowspan |
| 78355 | Valid bug | submenu a11y |
| 77830 | Valid bug | image visual jerk; durable CSS-cascade hypothesizing failure |
| 77530 | Valid or Out of scope | Tracking issue, 26 comments, most sub-items resolved; covers shape-gap 4 (long-thread) |
| 75215 | Valid bug | Body-is-Playwright-test (test code in place of natural-language steps); multi-block (Navigation + Navigation Link); steps_quality stress |

## Spot-check picks (round 0 calibration, per Q12)

- **Train, complex Valid bug:** `78342`
- **Train, easy Out of scope:** `78628`

Holdout issues are never spot-checked or read directly by the parent during draft-the-diff time (Q14).
