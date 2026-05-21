# Blueprint recipes

Copy-paste Blueprint step JSON for applying common preconditions when the URL Query API isn't enough. Pair this with `references/playground-url-builder.md`, which covers the URL/fragment encoding.

The general shape of the Blueprint fragment:

```json
{
  "landingPage": "/wp-admin/post-new.php",
  "login": true,
  "steps": [
    { "step": "...", "...": "..." },
    { "step": "...", "...": "..." }
  ]
}
```

Steps run in order, once, when Playground boots. Failures abort the boot — the repro then can't run, so verify any non-trivial Blueprint shape in a browser first if you can.

Log every step (and an output excerpt where applicable) in the report's "Preconditions applied" section. For `runPHP`, log the PHP code verbatim — the report is the only record of what executed.

## Default credentials

- Admin user: `admin`
- Admin password: `password`

These come from Playground itself; `login: true` in the Blueprint or `login=yes` in the query string logs you in. Don't put credentials in `runPHP`.

## Posts and content

### Seed a draft post with raw block markup

```json
{
  "step": "runPHP",
  "code": "<?php require_once '/wordpress/wp-load.php'; wp_insert_post(['post_title' => 'Repro: <issue-number>', 'post_status' => 'draft', 'post_type' => 'post', 'post_content' => '<!-- wp:paragraph --><p>Hello</p><!-- /wp:paragraph -->']);"
}
```

To navigate to the newly-created post, set `landingPage` to `/wp-admin/edit.php` and have the repro click into the draft; or capture the ID inside the PHP and write it to an option you read back via REST.

### Seed a post containing a Cover block

```json
{
  "step": "runPHP",
  "code": "<?php require_once '/wordpress/wp-load.php'; wp_insert_post(['post_title' => 'Repro', 'post_status' => 'draft', 'post_content' => '<!-- wp:cover {\"url\":\"https://s.w.org/style/images/about/WordPress-logotype-wmark.png\"} --><div class=\"wp-block-cover\"><img class=\"wp-block-cover__image-background\" src=\"https://s.w.org/style/images/about/WordPress-logotype-wmark.png\"/><div class=\"wp-block-cover__inner-container\"><!-- wp:paragraph --><p>Cover text</p><!-- /wp:paragraph --></div></div><!-- /wp:cover -->']);"
}
```

Cover/Image blocks that reference external URLs require `networking=yes` in the query string.

## Themes

### Activate an already-installed theme

```json
{ "step": "activateTheme", "themeFolderName": "twentytwentyfive" }
```

### Install + activate a theme from the WordPress.org directory

Prefer the `theme=` query param. If you need it in the Blueprint:

```json
{
  "step": "installTheme",
  "themeData": { "resource": "wordpress.org/themes", "slug": "twentytwentyfive" },
  "options": { "activate": true }
}
```

Requires `networking=yes`.

## Plugins

### Activate an already-installed plugin

```json
{ "step": "activatePlugin", "pluginPath": "classic-editor/classic-editor.php" }
```

### Install + activate a plugin from the WordPress.org directory

Prefer the `plugin=` query param. Blueprint form:

```json
{
  "step": "installPlugin",
  "pluginData": { "resource": "wordpress.org/plugins", "slug": "classic-editor" },
  "options": { "activate": true }
}
```

Requires `networking=yes`.

The Gutenberg plugin is installed by `gutenberg-branch=trunk` automatically — do not also install it via the plugin steps.

### Install a custom plugin from a URL

```json
{
  "step": "installPlugin",
  "pluginData": { "resource": "url", "url": "https://example.com/path/to/plugin.zip" },
  "options": { "activate": true }
}
```

For issues that depend on a third-party plugin not on wp.org, this avoids the previous `browser_file_upload` flow entirely — provided the zip is reachable at a public URL. If only a local zip exists, fall back to the wp-admin plugin-upload UI (see "Last-resort UI fallback" below).

## Users and roles

### Create a user with a specific role

```json
{
  "step": "runPHP",
  "code": "<?php require_once '/wordpress/wp-load.php'; wp_insert_user(['user_login' => 'author1', 'user_pass' => 'password', 'user_email' => 'author1@example.com', 'role' => 'author']);"
}
```

To log in as that user instead of `admin`, omit `login=yes` from the URL and have the plan log in via `wp-login.php` with the new credentials. The skill's default flow assumes admin; non-admin scenarios must be called out in the plan.

## Site options

### Set a single option

```json
{ "step": "setSiteOptions", "options": { "blogname": "Repro Site" } }
```

`setSiteOptions` accepts any number of keys in one call.

### Toggle a Gutenberg experiment

Experiments live in the `gutenberg-experiments` option as a JSON-encoded array.

```json
{ "step": "setSiteOptions", "options": { "gutenberg-experiments": { "gutenberg-block-bindings-ui": true } } }
```

Always note the experiment state in the report — experiments materially change the editor UI and skew repros.

## `wp-config.php` constants

```json
{ "step": "defineWpConfigConsts", "consts": { "WP_DEBUG": true, "WP_DEBUG_LOG": true, "SCRIPT_DEBUG": true } }
```

Use this when the issue references a constant (`WP_DEBUG`, `SCRIPT_DEBUG`, a custom `*_FORCE_*` flag in core/plugin code).

## Importing content

### Import a WXR file

```json
{ "step": "importWxr", "file": { "resource": "url", "url": "https://example.com/content.xml" } }
```

Requires `networking=yes`. Most repros are simpler to seed with a `runPHP` + `wp_insert_post` than to import WXR.

## Last-resort UI fallback

If a precondition genuinely can't be expressed as a Blueprint step or a wp.org install — for example, the issue requires a private build of a plugin distributed only as a local zip and there's no public URL to point `installPlugin` at — fall back to wp-admin UI:

1. Land at `/wp-admin/plugin-install.php?tab=upload`.
2. `browser_file_upload(<path>)` — see the path sandbox note in `references/playwright-patterns.md`.
3. Click "Install Now", then "Activate Plugin".

This is a consent gate in interactive mode (the file must be staged inside the project root) and a hard stop in CI mode (no human to consent). Prefer hosting the zip somewhere public and using the `installPlugin` step instead.
