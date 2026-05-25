# Report template

Render `report.md` using exactly the structure below. Replace placeholders in angle brackets. Omit sections that don't apply (e.g., per-attempt logs when the verdict came from triage and execution never ran), but keep the header and verdict line in every report.

The first non-blank line under the title must be the `**Verdict:**` line so the report is greppable. The report references the sibling `triage.md` for plan details rather than restating them — readers can open both files in the same dir.

```markdown
# Repro report: issue #<number> — <issue title>

**Verdict:** <Reproduced | Not reproduced | Inconclusive | Could not execute | Insufficient info | Out of scope>
**Issue:** <full URL>
**Triage:** [`./triage.md`](./triage.md) (verdict: `<Valid bug candidate | Out of scope | Insufficient info>`, confidence: `<high | low | n/a>`)
**Tested against:** Gutenberg `trunk` on hosted WordPress Playground (`playground.wordpress.net`)
**Attempts:** <n> of 3
**Date:** <ISO 8601 timestamp>

## Execution log

### Setup
- Playground URL: `<full URL navigated to in Step 5, including query params and fragment>`
- Blueprint (decoded, only if a Blueprint fragment was used):
  ```json
  { "landingPage": "...", "login": true, "steps": [ ... ] }
  ```

### Preconditions applied
- Via Query API: <list of params used, e.g. `theme=twentytwentyfive`, `plugin=classic-editor`>
- Via Blueprint steps: <list of step types used, e.g. `runPHP` seeded a draft post, `setSiteOptions` toggled `gutenberg-experiments`>
- ...

### Attempt 1
- Login: ok
- Navigation: `<URL>`
- Steps executed: 1–<n>
- Observed: <free text describing the resulting state>
- Console errors (filtered): <list, or "none">
- Network errors (filtered): <list, or "none">
- Outcome: <reproduced | not reproduced | timeout (step <n>) | error: <msg>>

### Attempt 2
<same shape; omit if loop stopped after attempt 1>

### Attempt 3
<same shape; omit if loop stopped earlier>

## Evidence

- Screenshot: `./bug-state.png` <only when verdict is Reproduced; else `./final-state.png`>
- Triage artifacts: `./triage.md`, `./issue-context.md`, downloaded images `./issue-attachment-*.png`
- Videos/GIFs referenced in issue: <list of URLs from triage, not downloaded>

## Notes

<Free text for Claude to flag anything a human should know that doesn't fit the structure: ambiguity in the plan that became apparent during execution, suspicious selectors used, environment oddities, unexpected console errors that did not change the verdict, hints from the issue thread about related PRs or issues.

If Step 2's triage-first discipline was broken — i.e., the run consulted `issue-context.md` or a downloaded image — log each consultation here: "Consulted `issue-context.md` to disambiguate step 3 — original wording was '…'". This is required, not optional.

If the triage frontmatter said `confidence: low`, this section must briefly explain why (copy or paraphrase the triage's `Verdict reasoning` line about confidence).>
```

## Notes on filling the template

- **Verdict line:** exactly one of the six values, no qualifiers. Caveats go in `Notes`. The `Out of scope` and `Insufficient info` verdicts here mirror what the triage said when the triage already decided; the four execution verdicts come from Step 5's loop.
- **Tested against:** if the plan used `gutenberg-pr=<n>` instead of `gutenberg-branch=trunk`, change the line to `Gutenberg PR #<n> on hosted WordPress Playground` so a reader knows the test environment differed. Also note any non-default `wp=` or `php=` pin.
- **Playground URL:** log the exact URL navigated to, including query params and fragment. The URL is the replay handle — without it the repro can't be re-run. If the Blueprint was base64-encoded, log the decoded JSON below the URL.
- **Filtered errors:** include the matched substring that caused the filter to admit the message (e.g., `[wp.blockEditor] …`), so a reviewer can sanity-check the filter.
- **Outcome strings:** stick to the exact strings `reproduced`, `not reproduced`, `timeout (step <n>)`, `error: <msg>` for machine-grepping later.
- **No restated plan.** The plan lives in `triage.md`. Don't copy `Preconditions`, `Steps`, `Expected`, or `Actual` into the report — link to the triage and let readers click through. The report's job is execution evidence, not plan documentation.
- **Low-confidence flag.** In CI mode, if the triage was `confidence: low` and the run auto-proceeded, prefix the verdict word with `[low confidence]`: `**Verdict:** [low confidence] Reproduced`. The `Notes` section must briefly explain why (paraphrase the triage's `Verdict reasoning`).
- **Triage-passthrough verdicts.** When the triage's verdict was `Out of scope` or `Insufficient info`, Step 5 never ran. Omit the per-attempt sections; keep the header, the verdict line, and a Notes section that copies the triage's `Verdict reasoning`.
