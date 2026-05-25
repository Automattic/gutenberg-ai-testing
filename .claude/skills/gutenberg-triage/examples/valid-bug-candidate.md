---
issue: WordPress/gutenberg#99001
issue_url: https://github.com/WordPress/gutenberg/issues/99001
nonce: a1b2c3d4
verdict: Valid bug candidate
confidence: high
generated_at: 2026-05-20T14:22:00Z
skill_version: gutenberg-triage 0.1.0
---

# Triage: Cover block toolbar renders above canvas instead of attached to block

## Verdict reasoning

Issue is labeled `[Type] Bug` and the repository state is open. Body contains a clear set of observable steps, an explicit expected behavior, and an explicit actual behavior described in plain text plus a screenshot. The referenced selector (`.wp-block-cover`) exists in the current trunk and the contextual toolbar code path at `packages/block-editor/src/components/block-tools/block-toolbar.js` was last touched two weeks ago. Confidence is `high`: the steps are unambiguous, no precondition is missing, and the bug area is identified in the codebase.

## Preconditions

- theme: Twenty Twenty-Five (default)
- plugins: none beyond Gutenberg
- user role: administrator (Playground default admin)
- post content: an empty post in the block editor
- site settings: none

## Steps

1. Open the block editor at `/wp-admin/post-new.php`.
2. Click the inserter and insert a Cover block.
3. Skip the placeholder by clicking "Skip" (no media required).
4. Click on the Cover block to select it.

## Expected

The block contextual toolbar attaches to the top edge of the selected Cover block, with the toolbar handles aligned to the block boundary.

## Actual (reported)

The toolbar renders pinned to the top of the editor canvas instead of attached to the block, and remains there when scrolling. The toolbar handles are misaligned by approximately the height of the editor header.

## Code findings

- `.wp-block-cover` selector still defined at `packages/block-library/src/cover/style.scss:1`.
- `BlockToolbar` component at `packages/block-editor/src/components/block-tools/block-toolbar.js:48` — last touched in `c1d7ba362a` (2026-05-08), a refactor of the popover positioning logic.
- recent commits touching the suspected area: `c1d7ba362a`, `917fafe544`, `e864163e14`.

## Notes

Screenshot in the issue shows the toolbar rendered at `top: 0` of the editor viewport rather than attached to the block. Re-stated in `Actual` above so the repro can act on the description alone without consulting the image.
