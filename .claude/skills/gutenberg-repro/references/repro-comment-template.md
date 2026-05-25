# Repro comment template

Used in CI mode only. Defines the shape of `comment-body.md`, the single comment that the repro job posts to the source issue when the verdict is `Reproduced` or `Not reproduced` AND the source issue lives in the same repo as the workflow (see SKILL.md Step 6).

Triage-only verdicts (`Out of scope`, `Insufficient info`) are handled by `/gutenberg-triage`'s own comment template (`../../gutenberg-triage/references/triage-comment-template.md`) and never reach this template.

The visible part above the fold must be scannable from the issue feed — keep it short. The detailed report goes inside a `<details>` block so triagers only expand it when they want more.

## Shape

```markdown
**Verdict: <Reproduced | Not reproduced>**<optional " [low confidence]">

<one-sentence summary, ≤200 chars>

Tested against Gutenberg `trunk` on hosted Playground · <n> attempt(s) · <duration>

<details>
<summary>Full report</summary>

<verbatim render of report.md per references/report-template.md>

</details>

<sub>Automated by `/gutenberg-repro` (CI mode). Re-run by removing and re-adding the `ai-reproduce` label. Triage and screenshots are available as [workflow artifacts on this run](<run-url>).</sub>
```

## Constraints

- **Verdict line.** Exactly one of `Reproduced` or `Not reproduced` — these are the only verdicts that produce a comment from the repro job. Other repro-job verdicts (`Could not execute`, `Inconclusive`) skip posting entirely (see SKILL.md Step 6).
- **Low-confidence suffix.** If Step 2 auto-proceeded on a triage with `confidence: low`, append the literal `[low confidence]` after the verdict word: `**Verdict: Reproduced [low confidence]**`. The `Notes` section of the embedded `report.md` must explain why (paraphrased from `triage.md`'s `Verdict reasoning`).
- **One-sentence summary.** ≤200 chars. For `Reproduced`: what was observed. For `Not reproduced`: what was tried.
- **Metadata line.** `Tested against Gutenberg \`trunk\` on hosted Playground · <n> attempt(s) · <duration>` — `<n>` is the number of attempts actually executed (1–3), `<duration>` is wall-clock from start of Step 3 to end of Step 5 formatted as `<m>m<s>s` (e.g., `4m17s`). If the plan used `gutenberg-pr=<n>` instead, replace `\`trunk\`` with `PR #<n>` so the comment surfaces the divergence.
- **No embedded screenshots.** GitHub issue comments cannot reference local files. v1 keeps screenshots in the workflow artifact and lets the trailer line direct readers there. Don't try to embed images via base64 or external image hosts.
- **Run URL.** Substitute `<run-url>` in the trailer with `$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID` (all three are set by GitHub Actions on every runner). The Artifacts section is at the bottom of that run page.
- **Full report rendered verbatim.** Inside the `<details>` block, render the entire content of `report.md` as produced per `references/report-template.md`. Do not restructure or trim. The report references `triage.md` rather than restating the plan, so the embedded content is execution-evidence-heavy and short on plan prose.
- **Pre-fold byte budget.** Everything above `<details>` should fit in roughly 600 chars including the verdict, summary sentence, and metadata line. If the summary sentence runs long, cut it — the full report has the detail.

## Why this shape

- **Single comment, not multiple.** Triagers shouldn't have to scroll through repro chatter; one comment with a fold is enough. The triage job's own comment (when posted at all) is a separate, earlier comment for separate verdicts — the two never collide.
- **Verdict-first formatting.** The bold verdict line is the most important signal — it shows up as the first line of the comment in the issue feed and email notifications.
- **Fold protects the issue thread.** The full report can run several hundred lines (execution log, three attempt logs, console/network noise). Burying it behind a `<summary>` keeps the thread readable while preserving everything.
- **No-comment exit when nothing useful.** Verdicts other than `Reproduced` / `Not reproduced` mean the repro didn't run cleanly; posting that to the issue would be noise. The workflow artifact has the full story for anyone who wants to debug.
