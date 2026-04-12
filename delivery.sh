#!/bin/bash
# delivery.sh — Automated delivery loop for az-delivery-team
# Usage: ./delivery.sh [--max-rounds N] [--auto-approve-stories]
#
# Drives Phase 0→1→2→3 automatically using delivery.json as state.
# Each Phase = one or more `claude` invocations.
# Phase 1 iterates Story-by-Story with fresh context per invocation.
# NO-GO loops back to Phase 1 with new FIX Stories.

set -euo pipefail

# ─── Defaults ───
STATE_FILE=".claude/delivery.json"
PROGRESS_FILE=".claude/progress.txt"
REPORTS_DIR=".claude/reports"
AGENTS_DIR=".claude/agents"
PHASE1_STALL_LIMIT=3
AUTO_APPROVE_STORIES=false

# ─── Cleanup temp files on exit ───
cleanup() {
  rm -f /tmp/delivery-prompt.* 2>/dev/null || true
  rm -f "${STATE_FILE}.tmp."* 2>/dev/null || true
  rm -f "${STATE_FILE}.pre-rollback" "${PROGRESS_FILE}.pre-rollback" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ─── Parse arguments ───
MAX_ROUNDS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-rounds)
      MAX_ROUNDS="$2"
      shift 2
      ;;
    --max-rounds=*)
      MAX_ROUNDS="${1#*=}"
      shift
      ;;
    --auto-approve-stories)
      AUTO_APPROVE_STORIES=true
      shift
      ;;
    *)
      echo "Warning: Unknown argument: $1"
      shift
      ;;
  esac
done

# ─── Preflight checks ───
if [ ! -f "$STATE_FILE" ]; then
  echo "Error: $STATE_FILE not found. Run /az-delivery-team first to set up the project."
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v claude &> /dev/null; then
  echo "Error: claude CLI is required. Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

if [ ! -d "$AGENTS_DIR" ]; then
  echo "Error: $AGENTS_DIR not found. Run /az-delivery-team first."
  exit 1
fi

# ─── Read maxRounds from JSON, CLI overrides ───
JSON_MAX_ROUNDS=$(jq -r '.maxRounds // 5' "$STATE_FILE")
MAX_ROUNDS="${MAX_ROUNDS:-$JSON_MAX_ROUNDS}"

# Validate maxRounds is a number
if ! [[ "$MAX_ROUNDS" =~ ^[0-9]+$ ]]; then
  echo "Error: --max-rounds must be a positive integer, got: $MAX_ROUNDS"
  exit 1
fi

# ─── Initialize progress file ───
if [ ! -f "$PROGRESS_FILE" ]; then
  cat > "$PROGRESS_FILE" << 'PROGRESS_INIT'
## Codebase Patterns

(Patterns discovered during implementation — domain-engineers append here)

---
PROGRESS_INIT
  echo "Created $PROGRESS_FILE"
fi

# ─── Ensure reports directory exists ───
mkdir -p "$REPORTS_DIR"

# ─── Helper: safe JSON update (atomic write) ───
json_update() {
  local jq_expr="$1"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  if jq "$jq_expr" "$STATE_FILE" > "$tmp"; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    echo "Error: jq update failed: $jq_expr"
    return 1
  fi
}

json_update_arg() {
  local jq_expr="$1"
  local arg_name="$2"
  local arg_value="$3"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  if jq --arg "$arg_name" "$arg_value" "$jq_expr" "$STATE_FILE" > "$tmp"; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    echo "Error: jq update failed: $jq_expr"
    return 1
  fi
}

# ─── Helper: read/update state ───
read_phase() { jq -r '.currentPhase' "$STATE_FILE"; }
read_round() { jq -r '.round' "$STATE_FILE"; }
update_phase() { json_update_arg '.currentPhase = $p' "p" "$1"; }
increment_round() { json_update '.round += 1'; }
reset_verification() {
  json_update '.verification.reports = (.verification.reports | to_entries | map(.value = null) | from_entries) | .verification.verdict = null'
}

# ─── Helper: story queries ───
get_next_stories_by_domain() {
  jq -r '
    [.stories[] | select(.passes == false and .blocked == false)]
    | group_by(.domain)
    | map(sort_by(.priority) | first)
    | .[]
    | "\(.domain)|\(.id)|\(.title)"
  ' "$STATE_FILE"
}

count_remaining_stories() {
  jq '[.stories[] | select(.passes == false and .blocked == false)] | length' "$STATE_FILE"
}

all_stories_pass() {
  local remaining
  remaining=$(count_remaining_stories)
  [ "$remaining" -eq 0 ]
}

has_blocked_stories() {
  local blocked
  blocked=$(jq '[.stories[] | select(.blocked == true)] | length' "$STATE_FILE")
  [ "$blocked" -gt 0 ]
}

# ─── Helper: create temp prompt file ───
new_prompt_file() {
  mktemp "/tmp/delivery-prompt.XXXXXX"
}

# ─── Helper: git rollback tag ─── [Gap 3: rollback]
tag_round_start() {
  local round="$1"
  local tag="delivery-round-${round}-start"
  if git rev-parse HEAD &>/dev/null; then
    git tag -f "$tag" HEAD 2>/dev/null || true
    echo "[Rollback] Tagged $tag"
  fi
}

rollback_to_round_start() {
  local round="$1"
  local tag="delivery-round-${round}-start"
  if git rev-parse "$tag" &>/dev/null; then
    echo "[Rollback] Preserving state files before reset..."
    # Save delivery state files — these contain issue tracking data we must not lose
    cp "$STATE_FILE" "${STATE_FILE}.pre-rollback"
    cp "$PROGRESS_FILE" "${PROGRESS_FILE}.pre-rollback" 2>/dev/null || true
    echo "[Rollback] Resetting code to $tag"
    git reset --hard "$tag"
    # Restore state files after reset
    cp "${STATE_FILE}.pre-rollback" "$STATE_FILE"
    cp "${PROGRESS_FILE}.pre-rollback" "$PROGRESS_FILE" 2>/dev/null || true
    rm -f "${STATE_FILE}.pre-rollback" "${PROGRESS_FILE}.pre-rollback"
    return 0
  else
    echo "[Rollback] Tag $tag not found, cannot rollback"
    return 1
  fi
}

# ─── Helper: check claude output for fallback signals ─── [Gap 2: completion signal]
check_output_for_signal() {
  local output="$1"
  local signal="$2"
  echo "$output" | grep -Fq "$signal"
}

# ─── Main loop ───
echo "============================================="
echo "  Delivery Loop — Max rounds: $MAX_ROUNDS"
echo "============================================="
echo ""

PHASE1_STALL_COUNT=0

while true; do
  PHASE=$(read_phase)
  ROUND=$(read_round)

  if [ "$ROUND" -gt "$MAX_ROUNDS" ]; then
    echo ""
    echo "⛔ Reached max rounds ($MAX_ROUNDS). Human intervention needed."
    echo "   Check $STATE_FILE and $REPORTS_DIR for details."
    exit 1
  fi

  echo "─────────────────────────────────────────────"
  echo "  Phase: $PHASE | Round: $ROUND / $MAX_ROUNDS"
  echo "─────────────────────────────────────────────"

  case "$PHASE" in

    # ═══════════════════════════════════════════
    # Phase 0: Readiness Check + Story Decomposition
    # ═══════════════════════════════════════════
    "phase0")
      echo "[Phase 0] Running readiness check + story decomposition..."

      DESIGN_DOCS=$(jq -r '.designDocs | join(", ")' "$STATE_FILE")

      # [Gap 1] Algorithmic prompt
      PROMPT_FILE=$(new_prompt_file)
      cat > "$PROMPT_FILE" <<PHASE0_EOF
You are the delivery orchestrator. Follow these steps exactly:

Step 1: Read ${AGENTS_DIR}/product-owner.md and ${AGENTS_DIR}/project-architect.md to understand their roles.
Step 2: Read the design documents: ${DESIGN_DOCS}
Step 3: Use the Agent tool to run BOTH agents in parallel:

  Agent A — Product Owner:
    a1. Perform Phase 0 Readiness Check (from its instructions) against the design documents
    a2. Save Readiness Report to ${REPORTS_DIR}/product-owner-readiness.md
    a3. Decompose the design documents into Stories and write them into ${STATE_FILE}
        - Each Story: {id:"US-xxx", domain, title, description, acceptanceCriteria, priority, passes:false, source:"prd", failCount:0, blocked:false, notes:""}
        - Size rule: if you cannot describe the change in 2-3 sentences, split it
        - Order: schema/migration (priority 1-N) -> backend/API -> frontend/UI
        - Every Story must include "Typecheck passes" in acceptanceCriteria
        - UI Stories must also include "Verify in browser"
    a4. Update ${STATE_FILE}: set phase0.po_ready = true if READY, false if NOT READY

  Agent B — Project Architect:
    b1. Perform Readiness Check (from its instructions) against the design documents
    b2. Save Readiness Report to ${REPORTS_DIR}/project-architect-readiness.md
    b3. Update ${STATE_FILE}: set phase0.arch_ready = true if READY, false if NOT READY

Step 4: Read ${STATE_FILE} and confirm both phase0.po_ready and phase0.arch_ready are set.
Step 5: Report the final readiness status and number of stories created.
PHASE0_EOF
      claude -p "$(cat "$PROMPT_FILE")" || true
      rm -f "$PROMPT_FILE"

      # Check gate
      PO_READY=$(jq -r '.phase0.po_ready' "$STATE_FILE")
      ARCH_READY=$(jq -r '.phase0.arch_ready' "$STATE_FILE")

      if [ "$PO_READY" = "true" ] && [ "$ARCH_READY" = "true" ]; then
        # Verify stories were actually created
        STORY_COUNT=$(jq '.stories | length' "$STATE_FILE")
        if [ "$STORY_COUNT" -eq 0 ]; then
          echo "[Phase 0] ❌ Readiness passed but no stories were created."
          echo "  Product Owner failed to decompose design documents into stories."
          exit 1
        fi

        # [Gap 4] Story review checkpoint
        echo ""
        echo "[Phase 0] ✅ Readiness passed. $STORY_COUNT stories created:"
        echo ""
        jq -r '.stories[] | "  \(.priority). [\(.domain)] \(.id): \(.title)"' "$STATE_FILE"
        echo ""

        if [ "$AUTO_APPROVE_STORIES" = "true" ]; then
          echo "[Phase 0] Auto-approving stories (--auto-approve-stories flag)."
        else
          echo "Review the stories above."
          echo "  - To approve and continue: press Enter"
          echo "  - To edit stories: edit $STATE_FILE, then press Enter"
          echo "  - To abort: press Ctrl+C"
          read -r || {
            echo ""
            echo "Error: stdin not interactive. Use --auto-approve-stories for non-interactive mode."
            exit 1
          }
        fi

        update_phase "phase1"
      else
        echo "[Phase 0] ❌ Readiness check failed."
        [ "$PO_READY" != "true" ] && echo "  - Product Owner: NOT READY (see $REPORTS_DIR/product-owner-readiness.md)"
        [ "$ARCH_READY" != "true" ] && echo "  - Architect: NOT READY (see $REPORTS_DIR/project-architect-readiness.md)"
        echo ""
        echo "Fix the design documents and re-run."
        exit 1
      fi
      ;;

    # ═══════════════════════════════════════════
    # Phase 1: Implementation (Story-by-Story)
    # ═══════════════════════════════════════════
    "phase1")
      echo "[Phase 1] Implementation — Story loop (round $ROUND)..."

      # [Gap 3] Tag round start for rollback
      tag_round_start "$ROUND"

      # Check if all stories are done
      if all_stories_pass; then
        echo "[Phase 1] ✅ All stories pass. Moving to Phase 2."
        update_phase "phase2"
        PHASE1_STALL_COUNT=0
        continue
      fi

      BEFORE_COUNT=$(count_remaining_stories)
      BATCH=$(get_next_stories_by_domain)

      if [ -z "$BATCH" ]; then
        echo "[Phase 1] ✅ No more stories to process. Moving to Phase 2."
        update_phase "phase2"
        PHASE1_STALL_COUNT=0
        continue
      fi

      echo "[Phase 1] Next batch:"
      echo "$BATCH" | while IFS='|' read -r domain story_id title; do
        echo "  - [$domain] $story_id: $title"
      done

      # Run domains sequentially to avoid parallel writes to delivery.json
      FAILED_STORIES=()
      while IFS='|' read -r domain story_id title; do
        [ -z "$domain" ] && continue
        echo ""
        echo "[Phase 1] ── $domain-engineer → $story_id: $title ──"

        STORY_JSON=$(jq --arg id "$story_id" '.stories[] | select(.id == $id)' "$STATE_FILE")
        AGENT_FILE="$AGENTS_DIR/${domain}-engineer.md"

        if [ ! -f "$AGENT_FILE" ]; then
          echo "  ⚠️ Agent file not found: $AGENT_FILE — skipping"
          continue
        fi

        # Algorithmic prompt — numbered steps
        PROMPT_FILE=$(new_prompt_file)
        cat > "$PROMPT_FILE" <<STORY_EOF
You are the ${domain}-engineer. Follow these steps exactly:

Step 1: Read your full instructions at ${AGENT_FILE}
Step 2: Read project context at ${AGENTS_DIR}/_context.md
Step 3: Read ${PROGRESS_FILE} — focus on the Codebase Patterns section at the top
Step 4: Read cross-domain log at ${AGENTS_DIR}/_cross-domain.md (if it exists)
Step 5: Read the Story below and plan your approach (break into vertical slices if needed)

## Your Story
${STORY_JSON}

Step 6: Implement via TDD:
  6a. Write a failing test for the first acceptance criterion
  6b. Run the test — confirm it FAILS
  6c. Write minimal code to make the test pass
  6d. Run the test — confirm it PASSES
  6e. Repeat 6a-6d for remaining acceptance criteria
  6f. Refactor if needed (keep tests green)
Step 7: Run the full typecheck and test suite
Step 8: If Step 7 passes:
  8a. Commit all changes: git commit -m "feat: ${story_id} - ${title}"
  8b. Update ${STATE_FILE}: set this story (id="${story_id}") passes to true
  8c. Reply with: <signal>STORY_DONE:${story_id}</signal>
Step 9: If Step 7 fails, fix the issues and retry from Step 7 (max 3 attempts)
  If still failing after 3 attempts:
  9a. Do NOT set passes to true
  9b. Write what you completed and what failed in the notes field of story "${story_id}" in ${STATE_FILE}
  9c. Commit any partial work that compiles
  9d. Reply with: <signal>STORY_STUCK:${story_id}</signal>
Step 10: Append to ${PROGRESS_FILE}:
  ## [date] - ${story_id}: ${title}
  - What was implemented
  - Files changed
  - Learnings for future iterations
  ---
Step 11: If you discovered reusable patterns, append to the Codebase Patterns section at the top of ${PROGRESS_FILE}
STORY_EOF

        # Run and capture output for fallback signal check [Gap 2]
        OUTPUT=""
        if OUTPUT=$(claude -p "$(cat "$PROMPT_FILE")" 2>&1 | tee /dev/stderr); then
          echo "[Phase 1] ✅ $story_id — claude exited successfully"
        else
          echo "[Phase 1] ⚠️ $story_id — claude exited with error"
          FAILED_STORIES+=("$story_id")
        fi
        rm -f "$PROMPT_FILE"

        # [Gap 2] Fallback: if JSON was not updated, check output for signal
        STORY_PASSES=$(jq --arg id "$story_id" -r '.stories[] | select(.id == $id) | .passes' "$STATE_FILE")
        if [ "$STORY_PASSES" != "true" ]; then
          if check_output_for_signal "$OUTPUT" "<signal>STORY_DONE:${story_id}</signal>"; then
            echo "[Phase 1] Signal detected but JSON not updated. Updating now."
            json_update_arg '(.stories[] | select(.id == $sid)).passes = true' "sid" "$story_id"
          elif check_output_for_signal "$OUTPUT" "<signal>STORY_STUCK:${story_id}</signal>"; then
            echo "[Phase 1] ⚠️ $story_id reported stuck via signal"
            FAILED_STORIES+=("$story_id")
          fi
        fi

      done <<< "$BATCH"

      # Report failures
      if [ ${#FAILED_STORIES[@]} -gt 0 ]; then
        echo ""
        echo "[Phase 1] ⚠️ Failed/stuck stories: ${FAILED_STORIES[*]}"
      fi

      # Detect Phase 1 stall
      AFTER_COUNT=$(count_remaining_stories)
      if [ "$AFTER_COUNT" -ge "$BEFORE_COUNT" ]; then
        PHASE1_STALL_COUNT=$((PHASE1_STALL_COUNT + 1))
        echo "[Phase 1] ⚠️ No progress this batch (stall $PHASE1_STALL_COUNT/$PHASE1_STALL_LIMIT)"
        if [ "$PHASE1_STALL_COUNT" -ge "$PHASE1_STALL_LIMIT" ]; then
          echo "[Phase 1] ⛔ Stalled $PHASE1_STALL_LIMIT times. Moving to Phase 2 for verification."
          update_phase "phase2"
          PHASE1_STALL_COUNT=0
        fi
      else
        PHASE1_STALL_COUNT=0
      fi

      echo "[Phase 1] Batch complete. Remaining: $AFTER_COUNT stories."
      ;;

    # ═══════════════════════════════════════════
    # Phase 2: Verification (7 agents in parallel)
    # ═══════════════════════════════════════════
    "phase2")
      echo "[Phase 2] Running verification (7 agents)..."

      # [Gap 1] Algorithmic prompt
      PROMPT_FILE=$(new_prompt_file)
      cat > "$PROMPT_FILE" <<PHASE2_EOF
You are the verification orchestrator. Follow these steps exactly:

Step 1: Read project context at ${AGENTS_DIR}/_context.md
Step 2: Use the Agent tool to run ALL 7 verification agents IN PARALLEL.
  For each agent, create a subagent with this briefing:
  - Read your full instructions at ${AGENTS_DIR}/<agent-name>.md
  - Read project context at ${AGENTS_DIR}/_context.md
  - Check ${REPORTS_DIR}/ for your previous report (if exists, do issue tracking: mark each finding as NEW/FIXED/STILL OPEN/REGRESSED)
  - Save your report to ${REPORTS_DIR}/<agent-name>.md

  The 7 agents:
  1. smoke-tester    -> ${REPORTS_DIR}/smoke-tester.md
  2. api-tester      -> ${REPORTS_DIR}/api-tester.md
  3. security-auditor -> ${REPORTS_DIR}/security-auditor.md
  4. red-team        -> ${REPORTS_DIR}/red-team.md
  5. uiux-qa        -> ${REPORTS_DIR}/uiux-qa.md
  6. performance-auditor -> ${REPORTS_DIR}/performance-auditor.md
  7. launch-readiness -> ${REPORTS_DIR}/launch-readiness.md

Step 3: After all 7 complete, read each report and extract the overall status (PASS or FAIL).
Step 4: Update ${STATE_FILE}: set verification.reports.<agent-name> to PASS or FAIL for each.
Step 5: Reply with: <signal>VERIFICATION_DONE</signal>
PHASE2_EOF
      claude -p "$(cat "$PROMPT_FILE")" || true
      rm -f "$PROMPT_FILE"

      # Validate: at least some reports were produced
      REPORTS_SET=$(jq '[.verification.reports | to_entries[] | select(.value != null)] | length' "$STATE_FILE")
      if [ "$REPORTS_SET" -lt 1 ]; then
        echo "[Phase 2] ⚠️ No verification reports produced (0/7). Retrying Phase 2."
        # Don't transition — loop will re-enter Phase 2
      else
        echo "[Phase 2] ✅ $REPORTS_SET/7 reports complete. Moving to Phase 3."
        update_phase "phase3"
      fi
      ;;

    # ═══════════════════════════════════════════
    # Phase 3: Acceptance Review
    # ═══════════════════════════════════════════
    "phase3")
      echo "[Phase 3] Running acceptance review..."

      CURRENT_ROUND="$ROUND"

      # [Gap 1] Algorithmic prompt
      PROMPT_FILE=$(new_prompt_file)
      cat > "$PROMPT_FILE" <<PHASE3_EOF
You are the acceptance reviewer. Follow these steps exactly:

Step 1: Read your full instructions at ${AGENTS_DIR}/acceptance-reviewer.md
Step 2: Read project context at ${AGENTS_DIR}/_context.md
Step 3: Read ALL verification reports from ${REPORTS_DIR}/
  Required: smoke-tester.md, api-tester.md, security-auditor.md, red-team.md, uiux-qa.md, performance-auditor.md, launch-readiness.md
Step 4: Follow your acceptance-reviewer instructions to:
  4a. Check report completeness
  4b. Read all reports and extract findings
  4c. Synthesize by dimension
  4d. Arbitrate any conflicts between agents
  4e. Test core flows against acceptance criteria
  4f. Make your decision: GO / CONDITIONAL GO / NO-GO
Step 5: Save your acceptance review to ${REPORTS_DIR}/acceptance-review.md
Step 6: Update ${STATE_FILE}: set verification.verdict to your decision string (exactly "GO" or "CONDITIONAL GO" or "NO-GO")
Step 7: If your verdict is NO-GO, follow "Findings to Story Conversion (Delivery Mode)" in your agent instructions:
  7a. Extract all FAIL/STILL OPEN/REGRESSED issues from the 7 reports
  7b. Convert each to a FIX Story (id: FIX-${CURRENT_ROUND}-xxx, source: "verification-round-${CURRENT_ROUND}")
  7c. Merge issues with same root cause into one Story
  7d. If a previous FIX Story recurred: set passes=false, increment failCount (do not duplicate)
  7e. If any failCount >= 3: set blocked=true
  7f. Append new FIX Stories to ${STATE_FILE} stories array
Step 8: Reply with: <signal>VERDICT:<your decision></signal>
PHASE3_EOF

      # Capture output for fallback signal
      OUTPUT=""
      OUTPUT=$(claude -p "$(cat "$PROMPT_FILE")" 2>&1 | tee /dev/stderr) || true
      rm -f "$PROMPT_FILE"

      # Check verdict — primary: JSON field
      VERDICT=$(jq -r '.verification.verdict' "$STATE_FILE")

      # [Gap 2] Fallback: if JSON not updated, check output signal
      if [ "$VERDICT" = "null" ] || [ -z "$VERDICT" ]; then
        if check_output_for_signal "$OUTPUT" "<signal>VERDICT:GO</signal>"; then
          VERDICT="GO"
          json_update_arg '.verification.verdict = $v' "v" "GO"
        elif check_output_for_signal "$OUTPUT" "<signal>VERDICT:CONDITIONAL GO</signal>"; then
          VERDICT="CONDITIONAL GO"
          json_update_arg '.verification.verdict = $v' "v" "CONDITIONAL GO"
        elif check_output_for_signal "$OUTPUT" "<signal>VERDICT:NO-GO</signal>"; then
          VERDICT="NO-GO"
          json_update_arg '.verification.verdict = $v' "v" "NO-GO"
        fi
      fi

      case "$VERDICT" in
        "GO")
          echo ""
          echo "============================================="
          echo "  🟢 GO — Delivery complete!"
          echo "============================================="
          echo "  Round: $ROUND / $MAX_ROUNDS"
          echo "  Reports: $REPORTS_DIR/"
          echo "  Final review: $REPORTS_DIR/acceptance-review.md"
          exit 0
          ;;
        "CONDITIONAL GO")
          echo ""
          echo "============================================="
          echo "  🟡 CONDITIONAL GO — Delivery complete with caveats"
          echo "============================================="
          if has_blocked_stories; then
            echo "  Blocked stories (need human intervention):"
            jq -r '.stories[] | select(.blocked == true) | "    - \(.id): \(.title)"' "$STATE_FILE"
          fi
          echo "  Reports: $REPORTS_DIR/"
          echo "  Final review: $REPORTS_DIR/acceptance-review.md"
          exit 0
          ;;
        "NO-GO")
          echo ""
          echo "[Phase 3] 🔴 NO-GO — Looping back to Phase 1"
          NEW_FIXES=$(jq --arg src "verification-round-$ROUND" '[.stories[] | select(.source == $src)] | length' "$STATE_FILE")
          echo "  New FIX stories added: $NEW_FIXES"

          # [Gap 3] Check if rollback is needed (all stories blocked = unrecoverable)
          TOTAL_BLOCKED=$(jq '[.stories[] | select(.blocked == true)] | length' "$STATE_FILE")
          TOTAL_REMAINING=$(count_remaining_stories)
          if [ "$TOTAL_REMAINING" -eq 0 ] && [ "$TOTAL_BLOCKED" -gt 0 ]; then
            echo "[Phase 3] ⛔ All remaining stories are blocked. Rolling back round $ROUND."
            rollback_to_round_start "$ROUND" || true
            echo "  Human intervention needed. Blocked stories:"
            jq -r '.stories[] | select(.blocked == true) | "    - \(.id): \(.title)"' "$STATE_FILE"
            exit 1
          fi

          increment_round
          update_phase "phase1"
          reset_verification
          ;;
        *)
          echo "⚠️ Unexpected verdict: '$VERDICT'"
          echo "Check $REPORTS_DIR/acceptance-review.md and $STATE_FILE"
          exit 1
          ;;
      esac
      ;;

    *)
      echo "Error: Unknown phase '$PHASE' in $STATE_FILE"
      exit 1
      ;;
  esac
done
