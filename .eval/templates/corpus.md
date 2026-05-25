# Eval corpus

10 issues from `WordPress/gutenberg`, split 7 train / 3 holdout. Stratification limited by corpus skew (8 predicted Valid bug candidate, 1 Out of scope, 0–1 Insufficient info).

## Train (7)

| # | Predicted verdict | Notes |
|---|---|---|
| 78628 | Out of scope | closed → labeling-gate trips |
| 78625 | Valid or Insufficient | "Columns on WP 7" — vague title |
| 78533 | Valid bug | Post Excerpt regression |
| 78342 | Valid bug | image copy-paste, complex (spot-check pick) |
| 78238 | Valid bug | Cover + YouTube |
| 77678 | Valid bug | RTC malformed input, cross-cutting |
| 76568 | Valid bug | writing flow regression |

## Holdout (3)

| # | Predicted verdict | Notes |
|---|---|---|
| 77939 | Valid bug | Table rowspan |
| 78355 | Valid bug | submenu a11y |
| 77830 | Valid bug | image visual jerk |

## Spot-check picks (round 0 calibration, per Q12)

- **Train, complex Valid bug:** `78342`
- **Train, easy Out of scope:** `78628`

Holdout issues are never spot-checked or read directly by the parent during draft-the-diff time (Q14).
