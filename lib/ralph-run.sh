#!/bin/bash
# ralph-run.sh — execute the iterative Claude loop for a feature

ralph_load_config

FEATURE=""
MAX_ITER=""
DRY_RUN=false
NO_SLEEP=false
RALPH_PROVIDER="${RALPH_PROVIDER:-claude}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      RALPH_PROVIDER="$2"
      shift 2 ;;
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
      echo "Usage: ralph run <feature> [--provider <name>] [--max-iterations N] [--dry-run] [--no-sleep]"
      echo ""
      echo "Options:"
      echo "  --provider <name>    AI provider to use: claude (default), codex"
      echo "  --max-iterations N   Maximum iterations before stopping"
      echo "  --dry-run            Show what would be executed without running"
      echo "  --no-sleep           Skip sleep between iterations"
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

# Recover from interrupted runs: if a section log exists but is empty,
# the previous run was killed before Claude finished. Uncheck that section's
# tasks so it gets retried.
RECOVERED=false
for log_file in "$LOGS_DIR"/section-*.md; do
  [[ -f "$log_file" ]] || continue
  if [[ ! -s "$log_file" ]]; then
    section_num=$(basename "$log_file" | sed 's/section-\([0-9]*\)\.md/\1/')
    ralph_uncheck_section "$PLAN" "$section_num"
    rm -f "$log_file"
    echo "Recovered incomplete Section $section_num (empty log from interrupted run)"
    RECOVERED=true
  fi
done

# Recount after recovery
if [[ "$RECOVERED" == true ]]; then
  SECTIONS_REMAINING=$(ralph_count_sections_remaining "$PLAN")
  SECTIONS_TOTAL=$(ralph_count_sections_total "$PLAN")
  SECTIONS_DONE=$((SECTIONS_TOTAL - SECTIONS_REMAINING))
  echo ""
fi

echo "Ralph v$RALPH_VERSION — running feature: $FEATURE"
echo "Plan: $SECTIONS_DONE/$SECTIONS_TOTAL task sections completed, $SECTIONS_REMAINING remaining"
echo "Max iterations: $MAX_ITER"
echo ""

# Validate provider
ralph_check_provider

# Build provider command (for dry-run display)
if [[ "$RALPH_PROVIDER" == "claude" ]]; then
  PROVIDER_CMD="claude -p \"...\" --allowedTools \"$RALPH_ALLOWED_TOOLS\""
  [[ -n "$RALPH_CLAUDE_FLAGS" ]] && PROVIDER_CMD+=" $RALPH_CLAUDE_FLAGS"
  [[ -n "$RALPH_PERMISSION_MODE" ]] && PROVIDER_CMD+=" --permission-mode $RALPH_PERMISSION_MODE"
  [[ -n "$RALPH_MCP_CONFIG" ]] && PROVIDER_CMD+=" --mcp-config $RALPH_MCP_CONFIG"
elif [[ "$RALPH_PROVIDER" == "codex" ]]; then
  PROVIDER_CMD="codex exec \"...\""
  [[ -n "$RALPH_CODEX_FLAGS" ]] && PROVIDER_CMD+=" $RALPH_CODEX_FLAGS"
fi

# Dry run — show command and exit
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Provider: $RALPH_PROVIDER"
  echo "[dry-run] Would execute:"
  echo "  $PROVIDER_CMD"
  echo ""
  echo "Prompt file: $PROMPT"
  echo "Plan file:   $PLAN"
  [[ "$RALPH_PROVIDER" == "claude" ]] && [[ -n "$RALPH_MCP_CONFIG" ]] && echo "MCP config:  $RALPH_MCP_CONFIG"
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
  echo "Starting ${RALPH_PROVIDER}..."

  # Execute provider (re-read prompt each time so mid-run edits take effect)
  # Output is tee'd to a log file for later reference
  # stderr is merged so errors are captured in both terminal and log
  START_TIME=$(date +%s)
  ralph_invoke_provider "$(cat "$PROMPT")" 2>&1 | tee "$LOG_FILE"
  EXIT_CODE=${PIPESTATUS[0]}
  ELAPSED=$(( $(date +%s) - START_TIME ))
  ELAPSED_MIN=$((ELAPSED / 60))
  ELAPSED_SEC=$((ELAPSED % 60))

  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "${RALPH_PROVIDER} exited with code $EXIT_CODE after ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
    if [[ ! -s "$LOG_FILE" ]]; then
      echo "No output was produced. Check your API key, network connection, or run '${RALPH_PROVIDER} --help' to debug."
    fi
    exit 1
  fi

  echo ""
  echo "--- Section $CURRENT_SECTION completed in ${ELAPSED_MIN}m ${ELAPSED_SEC}s ---"

  if [[ ! -s "$LOG_FILE" ]]; then
    echo "Warning: ${RALPH_PROVIDER} produced no output for Section $CURRENT_SECTION"
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
