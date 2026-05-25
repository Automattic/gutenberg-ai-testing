#!/usr/bin/env bash
# extract-verdict.sh — extract the `verdict:` value from the YAML
# frontmatter of a triage.md produced by /gutenberg-triage.
#
# The frontmatter format is defined in references/triage-template.md.
# This script and that template are the single source of truth for the
# verdict's wire format — keep them in sync if either changes.
#
# Prints the verdict value to stdout (one of: "Valid bug candidate",
# "Out of scope", "Insufficient info"). Trailing whitespace and inline
# `# comments` are stripped.
#
# Exits 0 with empty stdout when the file exists but contains no
# `verdict:` line — callers can treat empty as "missing".
#
# Exits non-zero when the file does not exist or is not readable.
#
# Usage:
#   extract-verdict.sh <path-to-triage.md>

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <path-to-triage.md>" >&2
    exit 2
fi

TRIAGE="$1"

if [[ ! -r "$TRIAGE" ]]; then
    echo "$0: cannot read $TRIAGE" >&2
    exit 1
fi

# Match the first `verdict:` line, strip the key + leading whitespace,
# strip any inline `# comment` suffix, strip trailing whitespace, and
# print. Returns empty stdout if no `verdict:` line exists.
awk '
    /^verdict:[[:space:]]/ {
        sub(/^verdict:[[:space:]]*/, "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        print
        exit
    }
' "$TRIAGE"
