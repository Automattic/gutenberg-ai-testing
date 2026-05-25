#!/usr/bin/env bash
# prefilter-candidates.sh — rank gutenberg issues by shape-gap coverage for
# corpus-expansion candidacy (PLAN amendment v2 decision 18, step 1).
#
# Pulls open + recently-closed WordPress/gutenberg issues via `gh`, scores
# each on shape signals that correlate with the 12 categories in PLAN
# amendment v2 decision 17, and writes a ranked TSV to .eval/candidates/.
#
# This script is intentionally cheap (~1-2 minutes, ~30-100 gh calls). The
# expensive cold-read step is separate (see score-candidates.sh).
#
# Usage:
#   .eval/scripts/prefilter-candidates.sh [--state open|closed|all]
#                                          [--limit 200]
#                                          [--exclude-current]
#                                          [--out .eval/candidates/prefilter.tsv]
#
# Defaults: --state all, --limit 200, --exclude-current, --out as shown.

set -uo pipefail
# Intentionally not -e: many of the per-issue heuristics are grep-based
# tests where a non-match returning 1 is normal flow control. Errors that
# matter are caught at the gh/jq level explicitly below.

# ---- Args -------------------------------------------------------------------

STATE="all"
LIMIT="200"
EXCLUDE_CURRENT="1"
OUT=".eval/candidates/prefilter.tsv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) STATE="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --no-exclude-current) EXCLUDE_CURRENT="0"; shift ;;
    --exclude-current) EXCLUDE_CURRENT="1"; shift ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$STATE" in
  open|closed|all) ;;
  *) echo "--state must be open|closed|all" >&2; exit 2 ;;
esac

command -v gh >/dev/null || { echo "gh not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not on PATH" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

# ---- Current corpus (to exclude) -------------------------------------------

CURRENT_CORPUS_NUMS=""
if [[ "$EXCLUDE_CURRENT" == "1" ]]; then
  if [[ -f .eval/templates/corpus.md ]]; then
    CURRENT_CORPUS_NUMS=$(grep -oE '^\| [0-9]{4,6} ' .eval/templates/corpus.md \
      | awk '{print $2}' | sort -u | tr '\n' ' ')
  fi
fi

is_in_corpus() {
  local n="$1"
  [[ -n "$CURRENT_CORPUS_NUMS" ]] || return 1
  [[ " $CURRENT_CORPUS_NUMS " == *" $n "* ]]
}

# ---- Fetch issue list -------------------------------------------------------

echo "fetching up to $LIMIT issues (state=$STATE) from WordPress/gutenberg..." >&2

GH_STATE_FLAG=""
case "$STATE" in
  open)   GH_STATE_FLAG="--state open" ;;
  closed) GH_STATE_FLAG="--state closed" ;;
  all)    GH_STATE_FLAG="--state all" ;;
esac

# Pull number, title, state, labels, comments count, body (truncated), createdAt.
# `gh issue list` only returns recent N; we get title/labels/state/comments cheaply,
# then per-issue body via `gh issue view`.
LIST_JSON=$(gh issue list \
  --repo WordPress/gutenberg \
  $GH_STATE_FLAG \
  --limit "$LIMIT" \
  --json number,title,state,labels,comments,createdAt,author,body)

TOTAL=$(echo "$LIST_JSON" | jq 'length')
echo "got $TOTAL issues; computing shape signals (body included in list call)..." >&2

# ---- Score each issue -------------------------------------------------------

# Output columns:
#   number  state  comments  labels_str  shape_flags  score  title
# shape_flags is a comma-separated list of matched shape-gap category tags
# from PLAN amendment v2 decision 17. score is the count of distinct shapes
# matched (higher = more interesting), with small bonuses for hard cases.

{
  printf "number\tstate\tcomments\tlabels\tshape_flags\tscore\ttitle\n"

  # Split rows by NUL so bodies with newlines stay intact. Each record is
  # a jq-emitted tab-separated row: number TAB state TAB comments TAB labels
  # TAB title TAB body_b64 (NUL terminator).
  ROWS_FILE=$(mktemp)
  trap 'rm -f "$ROWS_FILE"' EXIT
  # Use "-" as a placeholder for any field that might otherwise be empty —
  # bash read with whitespace IFS collapses adjacent tabs, which corrupts
  # field alignment when a field is empty.
  echo "$LIST_JSON" | jq -r '
    .[] |
    [ (.number|tostring),
      (.state // "-"),
      ((.comments|length)|tostring),
      (([.labels[].name] | join(",")) | if . == "" then "-" else . end),
      ((.title // "-") | gsub("\t"; " ") | .[0:120] | if . == "" then "-" else . end),
      (.body // "" | @base64 | if . == "" then "-" else . end)
    ] | @tsv
  ' > "$ROWS_FILE"

  N_SEEN=0
  while IFS=$'\t' read -r NUM STATE_ COMMENTS LABELS TITLE BODY_B64; do
    N_SEEN=$((N_SEEN+1))
    if [[ $((N_SEEN % 25)) -eq 0 ]]; then
      echo "  processed $N_SEEN issues..." >&2
    fi
    if is_in_corpus "$NUM"; then continue; fi
    [[ "$COMMENTS" =~ ^[0-9]+$ ]] || COMMENTS=0
    # Decode body. "-" sentinel means jq saw an empty/null body.
    if [[ "$BODY_B64" == "-" ]]; then
      BODY=""
    else
      BODY=$(printf '%s' "$BODY_B64" | base64 -d 2>/dev/null || echo "")
    fi
    [[ "$LABELS" == "-" ]] && LABELS=""
    [[ "$TITLE" == "-" ]] && TITLE=""

    FLAGS=()
    SCORE=0

    # Shape 8: thin body — either truly empty, or so short that the user
    # filled out essentially nothing of the issue template. Detecting "issue
    # template with only `_No response_` placeholders" by stripping the
    # placeholders and section headers then checking what's left.
    BODY_LEN=${#BODY}
    STRIPPED=$(printf '%s' "$BODY" \
      | sed -E 's/^[[:space:]]*#+[^[:cntrl:]]*$//g' \
      | sed -E 's/_no response_//gI' \
      | tr -d '[:space:]_-')
    STRIPPED_LEN=${#STRIPPED}
    if [[ "$BODY_LEN" -eq 0 ]] || [[ "$STRIPPED_LEN" -lt 80 ]]; then
      FLAGS+=("empty-body"); SCORE=$((SCORE+2))
    fi

    # Shape 2: video-only repro
    if echo "$BODY" | grep -qiE '\.(mov|mp4|webm)([)\"[:space:]]|$)' \
       && ! echo "$BODY" | grep -qiE '\.(png|jpg|jpeg)([)\"[:space:]]|$)'; then
      FLAGS+=("video-only"); SCORE=$((SCORE+2))
    fi

    # Shape 4: long thread (>25 comments)
    if [[ "$COMMENTS" -gt 25 ]]; then
      FLAGS+=("long-thread"); SCORE=$((SCORE+2))
    elif [[ "$COMMENTS" -gt 50 ]]; then
      FLAGS+=("very-long-thread"); SCORE=$((SCORE+3))
    fi

    # Shape 9: non-English content (heuristic: high-frequency Spanish/Portuguese
    # markers in body, plus CJK character detection via perl. False positives
    # possible; user verifies during curation.)
    if echo "$BODY" | grep -qiE '\b(estoy|hola|gracias|funciona|problema)\b' \
       || echo "$BODY" | grep -qiE '\b(é|não|está|fazendo|funcionando)\b' \
       || echo "$BODY" | perl -CSD -ne 'exit 0 if /[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]/; END { exit 1 }' 2>/dev/null; then
      FLAGS+=("non-english"); SCORE=$((SCORE+2))
    fi

    # Shape 5: multi-block / cross-package — body mentions ≥2 distinct block names
    BLOCK_COUNT=$(echo "$BODY" | grep -oE 'core/[a-z-]+' | sort -u | wc -l | tr -d ' ')
    if [[ "$BLOCK_COUNT" -ge 2 ]]; then
      FLAGS+=("multi-block"); SCORE=$((SCORE+2))
    fi

    # Shape 6: timing / performance markers — stricter to avoid matching the
    # word "seconds" in unrelated prose. Require specific race/timing terms.
    if echo "$BODY" | grep -qiE '\b(race condition|race-condition|timing issue|paint timing|debounce|throttle|jank|janky|flicker|flickering)\b'; then
      FLAGS+=("timing-perf"); SCORE=$((SCORE+2))
    fi

    # Shape 7: linked PR — has a #NNNN reference. Disabled by default
    # (47/74 hits in initial run — too common to discriminate). Re-enable
    # only if combined with another shape signal.
    # if echo "$BODY" | grep -qE '#[0-9]{4,6}'; then
    #   FLAGS+=("linked-pr"); SCORE=$((SCORE+1))
    # fi

    # Shape 10: pastebin / gist
    if echo "$BODY" | grep -qiE '\b(pastebin\.com|gist\.github\.com|jsfiddle\.net|codepen\.io)\b'; then
      FLAGS+=("external-paste"); SCORE=$((SCORE+2))
    fi

    # Shape 11: plugin-dependent
    if echo "$BODY" | grep -qiE '\b(woocommerce|yoast|jetpack|elementor|advanced custom fields|acf)\b' \
       && [[ "$LABELS" != *"WooCommerce"* ]]; then
      FLAGS+=("plugin-dep"); SCORE=$((SCORE+2))
    fi

    # Shape 12: closed-with-active-comments
    if [[ "$STATE_" == "CLOSED" ]] && [[ "$COMMENTS" -ge 3 ]]; then
      FLAGS+=("closed-active"); SCORE=$((SCORE+1))
    fi

    # Bonus: image-bearing (eligible for image_observations_restated stress)
    # Counts both Markdown image refs and direct png/jpg URLs in the body.
    IMG_COUNT=$(echo "$BODY" | grep -oE '\.(png|jpg|jpeg|gif|webp)' | wc -l | tr -d ' ')
    if [[ "$IMG_COUNT" -ge 3 ]]; then
      FLAGS+=("image-heavy"); SCORE=$((SCORE+2))
    fi

    # Shape 1: maintainer-flip / contested-comment heuristic — many comments
    # plus presence of "intentional" / "by design" / "wontfix" / "reopen"
    # tokens, OR a comment count between 6 and 25 (medium thread).
    if [[ "$COMMENTS" -ge 6 ]] && [[ "$COMMENTS" -le 25 ]]; then
      FLAGS+=("medium-thread"); SCORE=$((SCORE+1))
    fi

    # Skip issues that matched no shapes (no headroom signal at prefilter level).
    if [[ ${#FLAGS[@]} -eq 0 ]]; then continue; fi

    FLAGS_STR=$(IFS=,; echo "${FLAGS[*]}")

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$NUM" "$STATE_" "$COMMENTS" "$LABELS" "$FLAGS_STR" "$SCORE" "$TITLE"
  done < "$ROWS_FILE"
} | (read -r HEADER; echo "$HEADER"; sort -t$'\t' -k6,6 -nr) > "$OUT"

# ---- Summary ----------------------------------------------------------------

KEPT=$(( $(wc -l < "$OUT") - 1 ))
echo "wrote $OUT with $KEPT scored candidates (sorted by score desc)" >&2
echo "" >&2
echo "top 10 candidates:" >&2
head -11 "$OUT" | column -t -s $'\t' >&2 || head -11 "$OUT" >&2
echo "" >&2
echo "next: review the top 20-30, then run .eval/scripts/score-candidates.sh" >&2
echo "      against a curated subset to compute headroom scores via cold-read." >&2
