# Triage examples

Three synthetic but realistic `triage.md` specimens — one for each verdict the skill emits. Use these as pattern references when synthesizing a new triage; they show how the template in `../references/triage-template.md` looks when filled in for typical issue shapes.

The examples are anonymized (`<owner>/<repo>#<n>` placeholders, fake nonces, fake timestamps). They are not derived from any specific real issue.

| File | Verdict | Shape |
| --- | --- | --- |
| `valid-bug-candidate.md` | `Valid bug candidate` (high confidence) | Concrete editor bug with clear steps, expected/actual, and a `Code findings` block confirming the referenced symbol still exists. |
| `out-of-scope.md` | `Out of scope` | Enhancement request — label triage rejects before plan synthesis. Body sections are brief; verdict reasoning carries the load. |
| `insufficient-info.md` | `Insufficient info` | Vague body ("editor is broken") with no observable claim. Plan synthesis attempted and abandoned; body sections collapse to `n/a`. |

Each file is a complete, valid `triage.md` per the template — frontmatter is machine-extractable by `scripts/extract-verdict.sh`, body follows the prescribed section order.
