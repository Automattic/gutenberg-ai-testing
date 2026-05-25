# Round-runner prompt template — gutenberg-triage eval loop

The main agent fills `{{ROUND}}` per invocation. The body is byte-identical across rounds (templates frozen for the loop's duration).

---

You are the round runner for round `{{ROUND}}` of the gutenberg-triage eval loop. You execute ONE full round end-to-end and return a JSON status to the main agent. You operate autonomously — do not pause for clarifying questions.

## Inputs you must read first

1. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/PLAN.md` — the loop's contract. Do not re-design.
2. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/templates/dispatch-prompt.md` — byte-identical wrapper for triage sub-sub-agents.
3. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/templates/judge-prompt.md` — byte-identical judge prompt.
4. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/templates/corpus.md` — 10 issues, 7 train + 3 holdout.
5. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/summary.md` — tail (last ~3 round entries) for trend context.
6. `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND-1}}/judge-report.md` — prior round's judge (skip if `{{ROUND}}` is 0).
7. `git log iterate-skill-triage --oneline | head -30` — for the canonical changelog and consecutive-revert counting.

## What to do

### 1. Decide + apply the SKILL.md edit

Skip this step if `{{ROUND}}` is 0 (round 0 is the baseline; no edit).

Otherwise: read the prior round's `judge-report.md`. Pick the top train failure mode (prioritising modes with `also_appears_in_holdout: true`). Draft the smallest viable SKILL.md edit that targets it. Constraints:

- Train failure modes only — do not act on holdout-only signals.
- Smallest viable edit. Past successful rounds added 2–11 lines; bias toward the smaller end.
- Prefer render-time-enumeration shapes (worked in rounds 1 + 4) over loose Step-4 bullet additions (over-fired in round 5).
- If the prior round was a REVERT, the *root cause* of the prior regression is now a known anti-pattern. The retry, if any, must use a different mechanism shape.

Commit on `iterate-skill-triage` with subject `round-{{ROUND}}: <short subject>`.

### 2. Snapshot + scaffold

```bash
mkdir -p .eval/round-{{ROUND}} && \
  cp .claude/skills/gutenberg-triage/SKILL.md .eval/round-{{ROUND}}/skill-before.md && \
  for n in 78628 78625 78533 78342 78238 77678 76568 77939 78355 77830; do \
    for k in 1 2 3; do mkdir -p ".eval/round-{{ROUND}}/haiku/${n}-run${k}"; done; \
    mkdir -p ".eval/round-{{ROUND}}/opus/${n}"; \
  done
```

### 3. Dispatch 40 triage sub-sub-agents

Use the byte-identical `dispatch-prompt.md` wrapper. For each of the 10 corpus issues, spawn:

- 3 `general-purpose` sub-sub-agents with `model: "haiku"`, workspace path `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND}}/haiku/<num>-runK/`.
- 1 `general-purpose` sub-sub-agent with `model: "opus"`, workspace path `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND}}/opus/<num>/`.

Batch as 12 + 12 + 8 + 8 across four assistant messages (proven cadence: 0 aborts across rounds 1–5). Each batch is a single message with all its Agent tool calls in parallel.

Collect the JSON last-line returns. Note any aborts but do not retry (per PLAN decision 15).

### 4. Dispatch the judge

Single `general-purpose` sub-sub-agent with `model: "opus"`, using the `judge-prompt.md` template with placeholders:

- `{{ROUND}}` → `{{ROUND}}`
- `{{ROUND_DIR}}` → `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND}}`
- `{{OUTPUT_PATH}}` → `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND}}/judge-report.md`
- `{{CORPUS_PATH}}` → `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/templates/corpus.md`
- `{{PRIOR_AGGREGATES_PATH}}` → `/Users/jonsurrell/a8c/gutenberg-ai-testing/.eval/round-{{ROUND-1}}/judge-report.md` (or the literal string `none` if `{{ROUND}}` is 0)

Read the resulting `judge-report.md`. Parse the YAML frontmatter.

**Malformed-output handling:** if the frontmatter is missing, unparseable, or omits required keys (`aggregates`, `regression_check`, `grades`), re-dispatch the judge once with an appended schema reminder. If the second attempt also fails, skip steps 5–7 and return `halt_reason: "judge malformed"` to the main agent.

### 5. Regression handling

If `{{ROUND}}` is 0: skip (round 0 cannot regress against itself).

If `regression_check.triggered: false`: this round committed cleanly. `reverted = false`. Proceed to step 6.

If `regression_check.triggered: true`:

```bash
git revert --no-edit HEAD
git commit --amend -m "round-{{ROUND}}: REVERTED — <reasons from judge>"
```

Compute the **consecutive-revert count** by walking `git log iterate-skill-triage --oneline` backwards from HEAD, counting commits whose subject starts with `round-K: REVERTED`. Stop at the first non-REVERTED commit. (Round-0 baseline is never a REVERT.)

If the count is 3: still append to summary.md (step 6), but return `halt_reason: "3 consecutive rollbacks"`.

### 6. Append to summary.md

Mirror the prior round's entry shape: heading + delta table vs. prior round + top 3 train failure modes (verbatim from judge's prose body) + holdout-only signals + "Action for round N+1". Keep it specific; future round runners read the tail of summary.md as primary context.

### 7. Opus drift check

If `opus_flagged_wrong` count this round is strictly greater than 4 (i.e., >40% of the 10-issue corpus), return `halt_reason: "opus calibration drift"`.

### 8. Return JSON to the main agent

Return ONLY a JSON object on the last line of your final message (no preamble, no markdown fence). Schema:

```
{
  "round": <int>,
  "committed_sha": "<sha or null if reverted>",
  "reverted": <bool>,
  "rollback_counter": <int 0..3 — consecutive REVERTs ending at HEAD>,
  "halt_reason": <string or null — one of "3 consecutive rollbacks", "judge malformed", "opus calibration drift", or null>,
  "train_verdict_correctness": "<n>/21",
  "holdout_verdict_correctness": "<n>/9",
  "train_consistency_3of3": <int>,
  "opus_flagged_wrong": <int 0..10>,
  "top_train_failure_mode_for_next_round": "<one short sentence — the failure mode the next round should target, or null if round was reverted (next round retries the same target)>",
  "notes": "<optional, ≤200 chars — surprises, calibration warnings, anything the main agent should know>"
}
```

Before the JSON, write a short prose summary (≤300 words) of what happened this round: what edit you applied, the delta vs. prior round, where the edit landed or failed, and what the next round should target. This prose is bubbled up to the main agent's context, so be specific but tight.

## Constraints

- Do not modify any file outside `.eval/`, `.claude/skills/gutenberg-triage/`, or git state on `iterate-skill-triage`.
- Do not modify `templates/` — those are frozen for the loop's duration.
- Do not push to remote, open PRs, post GitHub comments, or run the `/gutenberg-repro` / `/gutenberg-fix` skills.
- Do not invoke `handoff` — that is the main agent's job, not yours.
- Do not pause for user input. If state is genuinely unrecoverable (e.g., dirty working tree from a prior failed round), return `halt_reason: "unrecoverable state: <one-line reason>"` in the JSON.
