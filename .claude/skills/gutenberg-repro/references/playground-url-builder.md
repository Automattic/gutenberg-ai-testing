# Playground URL builder

The skill drives a hosted WordPress Playground instance at `https://playground.wordpress.net/` instead of a local wp-env. This file documents how to build the URL the browser navigates to in Step 7.

Playground runs WordPress entirely in the browser via WebAssembly. There is no server to start, no port to allocate, no build step.

## Base URL

```
https://playground.wordpress.net/
```

## Query parameters used by this skill

| Param | Purpose | Example |
| --- | --- | --- |
| `gutenberg-branch` | Install Gutenberg from a branch. **Always `trunk`** for this skill — the whole point is testing fresh trunk. | `gutenberg-branch=trunk` |
| `gutenberg-pr` | Install Gutenberg from a PR number. Only use when the plan explicitly cites a PR (e.g., the issue body says "broken since #65337"). Mutually exclusive with `gutenberg-branch`. | `gutenberg-pr=65337` |
| `login` | Auto-login as `admin` / `password`. Always `yes`. | `login=yes` |
| `url` | Landing page inside WordPress. Pick the entry point implied by the plan. | `url=/wp-admin/post-new.php` |
| `networking` | Allow outbound HTTP from the WASM PHP runtime. Required if the repro fetches anything external (block patterns directory, image URLs, REST calls to wp.org). | `networking=yes` |
| `php` | Pin PHP version. Omit unless the issue cites a PHP-version-specific bug. Defaults to a current version. | `php=8.2` |
| `wp` | Pin WordPress version. Default (omitted) is `latest`; use `nightly` if the issue cites a Core trunk regression. | `wp=nightly` |
| `theme` | Install + activate a theme from the WordPress.org directory. Repeatable. | `theme=twentytwentyfive` |
| `plugin` | Install + activate a plugin from the WordPress.org directory. Repeatable. | `plugin=classic-editor` |
| `multisite` | Enable multisite. Set only when the issue is multisite-specific. | `multisite=yes` |
| `language` | Locale. Use when the issue is locale/i18n-specific. | `language=fr_FR` |

Params **not** to use:

- `mode=seamless` — strips the browser-style chrome. We want the full chrome so screenshots include the URL bar for context.
- `can-save=yes` — we don't persist anything; the report and screenshots live in the workspace dir.
- `lazy` — irrelevant to scripted Playwright runs.

## Default credentials

- Admin user: `admin`
- Admin password: `password`

Both are baked into Playground. The `login=yes` param logs you in automatically — Step 7's `wp-login.php` form-fill from the previous wp-env flow is gone.

## When query params are enough

For repros whose only preconditions are "trunk + a stock theme + maybe one wp.org plugin," the URL alone is sufficient. Example:

```
https://playground.wordpress.net/?gutenberg-branch=trunk&login=yes&url=/wp-admin/post-new.php&networking=yes
```

Drop straight into the post editor on trunk Gutenberg with admin logged in. No Blueprint needed.

## When you need a Blueprint

Use a Blueprint (passed in the URL fragment) when the plan requires any of:

- Creating a post with specific block markup before the user starts.
- Toggling a Gutenberg experiment (`gutenberg-experiments` option).
- Setting an arbitrary `wp_options` value (`setSiteOptions` step).
- Defining a `wp-config.php` constant (`defineWpConfigConsts`).
- Running ad-hoc PHP (`runPHP`).
- Switching to a theme that isn't on wp.org and `theme=` won't reach.

See `references/blueprint-recipes.md` for the step shapes.

## Blueprint delivery: URL fragment

Pass the Blueprint as a URL fragment (the part after `#`). The fragment never reaches a server — Playground's bootstrap JS reads `window.location.hash` on load. Two encodings work:

### JSON fragment (preferred when small)

```
https://playground.wordpress.net/#{"landingPage":"/wp-admin/post-new.php","login":true,"steps":[...]}
```

URL-encode special chars in the JSON with `encodeURIComponent` before appending. Practical limit: a few KB. Most repro blueprints fit easily.

### Base64 fragment (preferred when large or copy-pasted)

```
https://playground.wordpress.net/#<base64-encoded-json>
```

More compact and shell-safe. Use when the JSON contains long PHP code blocks, or when the URL would otherwise be hard to log.

```bash
BP_JSON='{"landingPage":"/wp-admin/post-new.php","login":true,"steps":[...]}'
echo -n "$BP_JSON" | base64 | tr -d '\n'
```

Then prepend `https://playground.wordpress.net/#` to the output.

### Query params + Blueprint together

You can combine: `https://playground.wordpress.net/?gutenberg-branch=trunk&networking=yes#<blueprint>`. The query string sets the environment knobs Playground reads early (Gutenberg branch, networking, PHP/WP versions); the Blueprint runs once WordPress is up. Always put `gutenberg-branch=trunk` and `networking=yes` in the query string, not the Blueprint, so Gutenberg is installed before any Blueprint step runs.

### Top-level Blueprint fields

Beyond `steps`, the fragment can carry these top-level fields (subset relevant to this skill):

- `landingPage` — same as the `url` query param but inside the Blueprint. If set, omit `url=` from the query string to avoid divergence.
- `login` — boolean; same as `login=yes`. Either is fine; if you're already passing a Blueprint, just put it here.
- `preferredVersions` — `{ "php": "8.2", "wp": "nightly" }`. Equivalent to the `php=` and `wp=` query params.

## URL hygiene

- Always log the **exact** URL you navigate to in the report's Setup section. The fragment is the only record of what preconditions Playground applied — without it the repro is not replayable.
- If using base64, also log the decoded JSON in the report so a human can inspect what ran.
- Do not log the URL in CI logs if the Blueprint contains anything sensitive (it shouldn't — but check `runPHP` strings before logging).

## Example URLs

**Bare repro (no preconditions):**
```
https://playground.wordpress.net/?gutenberg-branch=trunk&login=yes&url=/wp-admin/post-new.php&networking=yes
```

**With theme switch and one wp.org plugin:**
```
https://playground.wordpress.net/?gutenberg-branch=trunk&login=yes&url=/wp-admin/post-new.php&networking=yes&theme=twentytwentyfive&plugin=classic-editor
```

**With a Blueprint that seeds a draft post:**
```
https://playground.wordpress.net/?gutenberg-branch=trunk&networking=yes#{"landingPage":"/wp-admin/edit.php","login":true,"steps":[{"step":"runPHP","code":"<?php require_once '/wordpress/wp-load.php'; wp_insert_post(['post_title'=>'Repro 12345','post_status'=>'draft','post_content'=>'<!-- wp:cover {\"url\":\"https://example.com/img.jpg\"} --><div class=\"wp-block-cover\"></div><!-- /wp:cover -->']);"}]}
```

After the Blueprint runs, navigate the browser to the seeded post's edit URL — fetch the ID inside the `runPHP` and stash it in an option you read back, or just hop to `edit.php` and click the post (cheaper if there's only one).
