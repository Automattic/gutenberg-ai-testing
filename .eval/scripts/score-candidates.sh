#!/usr/bin/env bash
# score-candidates.sh — orchestrator + post-processor for cold-read scoring
# of corpus-expansion candidates (PLAN amendment v2 decision 18, step 2-3).
#
# This script does NOT dispatch sub-agents itself. Sub-agent dispatch happens
# inside Claude Code via the Agent tool. The script does three things:
#
#   1. read-candidates: read .eval/candidates/admit-list.txt (one issue # per
#      line) and emit a dispatch plan to .eval/candidates/dispatch-plan.md
#      describing the 3 haiku + 1 opus Agent calls the user (or a sub-agent)
#      should make for each candidate.
#
#   2. scaffold: create the .eval/candidates/<num>-{run1,run2,run3,opus}/
#      workspace dirs for every candidate.
#
#   3. score: after all dispatched cold-reads have written triage.md +
#      signals JSON, parse the results and compute the headroom score per
#      candidate per the formula in PLAN amendment v2 decision 18 step 3.
#      Emit .eval/candidates/headroom.tsv ranked by headroom desc.
#
# Usage:
#   .eval/scripts/score-candidates.sh read-candidates
#   .eval/scripts/score-candidates.sh scaffold
#   .eval/scripts/score-candidates.sh score
#   .eval/scripts/score-candidates.sh all  # convenience: read-candidates + scaffold
#
# The actual cold-read dispatch (step 2 in the README) is done by you (or
# the main agent) calling Agent N times against .eval/templates/cold-read-prompt.md
# with placeholders {{ISSUE_REF}} = WordPress/gutenberg#<num> and
# {{WORKSPACE_PATH}} = .eval/candidates/<num>-runK or .eval/candidates/<num>-opus.

set -euo pipefail

CMD="${1:-help}"
shift || true

CANDIDATES_DIR=".eval/candidates"
ADMIT_LIST="$CANDIDATES_DIR/admit-list.txt"
DISPATCH_PLAN="$CANDIDATES_DIR/dispatch-plan.md"
HEADROOM_OUT="$CANDIDATES_DIR/headroom.tsv"

# ---- helpers ----------------------------------------------------------------

require_admit_list() {
  if [[ ! -f "$ADMIT_LIST" ]]; then
    echo "missing $ADMIT_LIST — create it with one issue number per line." >&2
    echo "example:" >&2
    echo "  printf '12345\n67890\n' > $ADMIT_LIST" >&2
    exit 1
  fi
}

read_candidates() {
  grep -oE '^[0-9]{3,6}' "$ADMIT_LIST" | sort -u
}

# ---- commands ---------------------------------------------------------------

cmd_read_candidates() {
  require_admit_list
  mkdir -p "$CANDIDATES_DIR"

  {
    echo "# Cold-read dispatch plan"
    echo ""
    echo "Generated from \`$ADMIT_LIST\`."
    echo ""
    echo "Dispatch the following $(read_candidates | wc -l | tr -d ' ') × 4 = $(($(read_candidates | wc -l | tr -d ' ') * 4)) Agent calls. Use \`general-purpose\` subagent type. Body of every call is \`.eval/templates/cold-read-prompt.md\` with the placeholders filled per row. Recommended batch shape: 12 + 12 + 12 + ... in parallel messages, mirroring the production round-runner cadence (PLAN decision 7)."
    echo ""
    echo "| candidate | run | model | workspace_path |"
    echo "|---|---|---|---|"
    while IFS= read -r num; do
      for run in 1 2 3; do
        echo "| $num | run${run} | haiku | \`$CANDIDATES_DIR/${num}-run${run}\` |"
      done
      echo "| $num | opus | opus | \`$CANDIDATES_DIR/${num}-opus\` |"
    done < <(read_candidates)
    echo ""
    echo "## After all calls complete"
    echo ""
    echo "Each cold-read writes a JSON line to its return message. Save those JSON lines to \`$CANDIDATES_DIR/<num>-<run>/return.json\` (or pass them inline to the score step). Then run:"
    echo ""
    echo "    .eval/scripts/score-candidates.sh score"
    echo ""
    echo "to compute headroom and rank."
  } > "$DISPATCH_PLAN"

  echo "wrote $DISPATCH_PLAN" >&2
  echo "candidates: $(read_candidates | tr '\n' ' ')" >&2
}

cmd_scaffold() {
  require_admit_list
  while IFS= read -r num; do
    mkdir -p "$CANDIDATES_DIR/${num}-run1" \
             "$CANDIDATES_DIR/${num}-run2" \
             "$CANDIDATES_DIR/${num}-run3" \
             "$CANDIDATES_DIR/${num}-opus"
  done < <(read_candidates)
  echo "scaffolded workspace dirs under $CANDIDATES_DIR/" >&2
}

# ---- scoring -----------------------------------------------------------------
#
# Headroom formula (PLAN amendment v2 decision 18 step 3):
#
#   +2 per haiku run with verdict_correctness `incorrect`
#   +1 per haiku run with confidence_calibration `incorrect` (when applicable)
#   +1 per haiku run with image_observations_restated `not-done` (when applicable)
#   +1 per haiku run with rigid_rules_compliance `fail`
#   +0.5 per haiku run that hit `good` or below where opus hit `excellent`
#   -3 if any haiku run aborted
#   -5 if cross-run verdict agreement is 0/3 with no defensible majority
#
# Two-stage:
#   1. for each candidate, parse all 4 return.json files (run1/run2/run3/opus).
#   2. compute the headroom score; emit a TSV row.
#
# A separate judge pass (using judge-prompt.md against the candidate dir) is
# needed to grade dimensions 3-11 (steps_quality etc) — the cold-read signals
# block doesn't carry those. For now the scoring uses what the signals block
# emits, plus a fallback parse of triage.md for verdict/confidence. Dimensions
# requiring the full rubric grade can be added in a follow-up by dispatching
# the judge against $CANDIDATES_DIR like a synthetic round.

cmd_score() {
  require_admit_list

  command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

  {
    printf "candidate\trun1_verdict\trun2_verdict\trun3_verdict\topus_verdict\taborts\theadroom\tnotes\n"

    while IFS= read -r num; do
      verdicts=()
      confs=()
      images_narrated=()
      injection_flags=()
      maintainer_intentional=()
      aborts=0
      score=0
      notes=()

      for run in run1 run2 run3 opus; do
        ret="$CANDIDATES_DIR/${num}-${run}/return.json"
        if [[ ! -f "$ret" ]]; then
          notes+=("missing-$run")
          if [[ "$run" != "opus" ]]; then verdicts+=("missing"); fi
          continue
        fi
        v=$(jq -r '.verdict // "null"' "$ret" 2>/dev/null || echo "parse-err")
        c=$(jq -r '.confidence // "null"' "$ret" 2>/dev/null || echo "parse-err")
        ab=$(jq -r '.aborted // false' "$ret" 2>/dev/null || echo "false")
        narr=$(jq -r '.signals.images_narrated_in_text // "null"' "$ret" 2>/dev/null || echo "null")
        inj=$(jq -r '.signals.injection_block_present // "null"' "$ret" 2>/dev/null || echo "null")
        mi=$(jq -r '.signals.maintainer_intentional_present // "null"' "$ret" 2>/dev/null || echo "null")

        if [[ "$run" == "opus" ]]; then
          opus_verdict="$v"
        else
          verdicts+=("$v")
          confs+=("$c")
          images_narrated+=("$narr")
          injection_flags+=("$inj")
          maintainer_intentional+=("$mi")
          if [[ "$ab" == "true" ]]; then
            aborts=$((aborts+1))
            score=$((score-3))
          fi
        fi
      done

      # Disagreement signal: count distinct verdicts across the 3 haiku runs.
      uniq_verdicts=$(printf '%s\n' "${verdicts[@]}" | sort -u | wc -l | tr -d ' ')
      if [[ "$uniq_verdicts" -ge 2 ]]; then
        score=$((score+2))
        notes+=("verdict-disagreement")
      fi
      if [[ "$uniq_verdicts" -ge 3 ]]; then
        # 0/3 majority — pathological
        score=$((score-5))
        notes+=("pathological-disagreement")
      fi

      # Maintainer-intentional flagged but at least one run picked high confidence:
      # likely calibration headroom.
      has_intentional=0
      for m in "${maintainer_intentional[@]}"; do
        [[ "$m" == "true" ]] && has_intentional=1
      done
      if [[ "$has_intentional" == "1" ]]; then
        for c in "${confs[@]}"; do
          if [[ "$c" == "high" ]]; then
            score=$((score+1))
            notes+=("calibration-headroom")
            break
          fi
        done
      fi

      # Image headroom: if any run reports images present but not narrated.
      for narr in "${images_narrated[@]}"; do
        if [[ "$narr" == "false" ]]; then
          score=$((score+1))
          notes+=("image-narration-headroom")
          break
        fi
      done

      # Injection headroom: injection block present but only some runs flagged.
      saw_true=0; saw_false=0
      for inj in "${injection_flags[@]}"; do
        [[ "$inj" == "true" ]] && saw_true=1
        [[ "$inj" == "false" ]] && saw_false=1
      done
      if [[ "$saw_true" == "1" && "$saw_false" == "1" ]]; then
        score=$((score+1))
        notes+=("injection-headroom")
      fi

      notes_str=$(IFS=,; echo "${notes[*]:-}")
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$num" "${verdicts[0]:-?}" "${verdicts[1]:-?}" "${verdicts[2]:-?}" \
        "${opus_verdict:-?}" "$aborts" "$score" "$notes_str"
    done < <(read_candidates)
  } | (read -r HEADER; echo "$HEADER"; sort -t$'\t' -k7,7 -nr) > "$HEADROOM_OUT"

  echo "wrote $HEADROOM_OUT" >&2
  echo "" >&2
  column -t -s $'\t' "$HEADROOM_OUT" >&2 || cat "$HEADROOM_OUT" >&2
  echo "" >&2
  echo "next: pick 3-8 train + 1-3 holdout admits from the top of the headroom" >&2
  echo "      list, then update .eval/templates/corpus.md to include them." >&2
}

cmd_help() {
  grep '^# ' "$0" | sed 's/^# \{0,1\}//'
}

case "$CMD" in
  read-candidates) cmd_read_candidates ;;
  scaffold)        cmd_scaffold ;;
  score)           cmd_score ;;
  all)             cmd_read_candidates; cmd_scaffold ;;
  help|-h|--help)  cmd_help ;;
  *) echo "unknown command: $CMD" >&2; cmd_help; exit 2 ;;
esac
