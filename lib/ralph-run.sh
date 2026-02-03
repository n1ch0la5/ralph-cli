#!/bin/bash
# ralph-run.sh — execute the iterative Claude loop for a feature

ralph_load_config

FEATURE=""
MAX_ITER=""
DRY_RUN=false
NO_SLEEP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations)
      MAX_ITER="$2"
      shift 2 ;;
    --dry-run)
      DRY_RUN=true
      shift ;;
    --no-sleep)
      NO_SLEEP=true
      shift ;;
    --help|-h)
      echo "Usage: ralph run <feature> [--max-iterations N] [--dry-run] [--no-sleep]"
      exit 0 ;;
    -*)
      echo "Unknown option: $1"
      exit 1 ;;
    *)
      FEATURE="$1"
      shift ;;
  esac
done

if [[ -z "$FEATURE" ]]; then
  echo "Usage: ralph run <feature>"
  echo "  Run 'ralph status' to see available features."
  exit 1
fi

MAX_ITER="${MAX_ITER:-$RALPH_MAX_ITERATIONS}"
FEATURE_PATH="$(ralph_feature_path "$FEATURE")"
PLAN="$FEATURE_PATH/$RALPH_PLAN_FILE"
SPEC="$FEATURE_PATH/$RALPH_SPEC_FILE"
PROMPT="$FEATURE_PATH/$RALPH_PROMPT_FILE"

# Validate required files
ralph_require_file "$PLAN" "$RALPH_PLAN_FILE"
ralph_require_file "$SPEC" "$RALPH_SPEC_FILE"
ralph_require_file "$PROMPT" "$RALPH_PROMPT_FILE"

# Check for remaining task sections
SECTIONS_REMAINING=$(ralph_count_sections_remaining "$PLAN")
if [[ "$SECTIONS_REMAINING" -eq 0 ]]; then
  echo "All tasks complete for '$FEATURE'."
  exit 0
fi

SECTIONS_TOTAL=$(ralph_count_sections_total "$PLAN")
SECTIONS_DONE=$((SECTIONS_TOTAL - SECTIONS_REMAINING))

LOGS_DIR="$FEATURE_PATH/logs"
ACTION_ITEMS="$FEATURE_PATH/action-items.md"
mkdir -p "$LOGS_DIR"

echo "Ralph v$RALPH_VERSION — running feature: $FEATURE"
echo "Plan: $SECTIONS_DONE/$SECTIONS_TOTAL task sections completed, $SECTIONS_REMAINING remaining"
echo "Max iterations: $MAX_ITER"
echo ""

# Build base claude command (for dry-run display)
CLAUDE_CMD="claude -p \"...\" --allowedTools \"$RALPH_ALLOWED_TOOLS\""
[[ -n "$RALPH_CLAUDE_FLAGS" ]] && CLAUDE_CMD+=" $RALPH_CLAUDE_FLAGS"
[[ -n "$RALPH_PERMISSION_MODE" ]] && CLAUDE_CMD+=" --permission-mode $RALPH_PERMISSION_MODE"
[[ -n "$RALPH_MCP_CONFIG" ]] && CLAUDE_CMD+=" --mcp-config $RALPH_MCP_CONFIG"

# Dry run — show command and exit
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would execute:"
  echo "  $CLAUDE_CMD"
  echo ""
  echo "Prompt file: $PROMPT"
  echo "Plan file:   $PLAN"
  [[ -n "$RALPH_MCP_CONFIG" ]] && echo "MCP config:  $RALPH_MCP_CONFIG"
  exit 0
fi

# Main loop
for ((i=1; i<=MAX_ITER; i++)); do
  SECTIONS_REMAINING=$(ralph_count_sections_remaining "$PLAN")
  if [[ "$SECTIONS_REMAINING" -eq 0 ]]; then
    echo ""
    echo "All tasks complete!"
    break
  fi

  SECTIONS_TOTAL=$(ralph_count_sections_total "$PLAN")
  SECTIONS_DONE=$((SECTIONS_TOTAL - SECTIONS_REMAINING))

  CURRENT_SECTION=$((SECTIONS_DONE + 1))
  LOG_FILE="$LOGS_DIR/section-${CURRENT_SECTION}.md"

  echo "=== Iteration $i — Section $CURRENT_SECTION/$SECTIONS_TOTAL — $SECTIONS_REMAINING remaining ==="

  # Execute claude (re-read prompt each time so mid-run edits take effect)
  # Output is tee'd to a log file for later reference
  claude -p "$(cat "$PROMPT")" --allowedTools "$RALPH_ALLOWED_TOOLS" $RALPH_CLAUDE_FLAGS \
    ${RALPH_PERMISSION_MODE:+--permission-mode "$RALPH_PERMISSION_MODE"} \
    ${RALPH_MCP_CONFIG:+--mcp-config "$RALPH_MCP_CONFIG"} \
    | tee "$LOG_FILE"
  EXIT_CODE=${PIPESTATUS[0]}

  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "Claude exited with code $EXIT_CODE"
    exit 1
  fi

  if [[ "$NO_SLEEP" != true ]]; then
    sleep "$RALPH_SLEEP_SECONDS"
  fi
done

# Final status
echo ""
SECTIONS_REMAINING=$(ralph_count_sections_remaining "$PLAN")
SECTIONS_TOTAL=$(ralph_count_sections_total "$PLAN")
SECTIONS_DONE=$((SECTIONS_TOTAL - SECTIONS_REMAINING))

if [[ "$SECTIONS_REMAINING" -eq 0 ]]; then
  echo "Done — $SECTIONS_TOTAL/$SECTIONS_TOTAL task sections completed."
else
  echo "Stopped after $MAX_ITER iterations — $SECTIONS_DONE/$SECTIONS_TOTAL sections completed, $SECTIONS_REMAINING remaining."
fi

echo "Logs saved to: $RALPH_FEATURE_DIR/$FEATURE/logs/"

# Display action items and generate clipboard-ready prompt
if [[ -f "$ACTION_ITEMS" ]] && [[ -s "$ACTION_ITEMS" ]]; then
  echo ""
  echo "========================================"
  echo "ACTION ITEMS — manual steps required:"
  echo "========================================"
  cat "$ACTION_ITEMS"
  echo "========================================"

  # Build a prompt for pasting into Claude
  FEATURE_DIR_REL="$RALPH_FEATURE_DIR/$FEATURE"
  FOLLOWUP_PROMPT="I just used ralph to implement the '$FEATURE' feature.

Read these files to understand what was built:
- $FEATURE_DIR_REL/$RALPH_SPEC_FILE — original requirements
- $FEATURE_DIR_REL/$RALPH_PLAN_FILE — task list (completed items marked [x])
- $FEATURE_DIR_REL/logs/ — output from each iteration (section-1.md, section-2.md, etc.)

The following manual steps are still needed:

$(cat "$ACTION_ITEMS")

For each action item:
1. Tell me what to do (exact commands or steps)
2. Verify it worked
3. Flag any issues

If something looks wrong in the logs or implementation, let me know before we proceed."

  # Save to file for reference
  FOLLOWUP_FILE="$FEATURE_PATH/followup-prompt.md"
  echo "$FOLLOWUP_PROMPT" > "$FOLLOWUP_FILE"

  echo ""
  echo "Follow-up prompt:"
  echo "========================================"
  echo ""
  echo "$FOLLOWUP_PROMPT"
  echo ""
  echo "========================================"
  echo ""
  echo "Saved to: $RALPH_FEATURE_DIR/$FEATURE/followup-prompt.md"
else
  echo ""
  echo "No manual action items — all done."
fi

if [[ "$SECTIONS_REMAINING" -gt 0 ]]; then
  exit 1
fi
