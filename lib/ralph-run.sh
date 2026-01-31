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

# Check for remaining tasks
REMAINING=$(ralph_count_remaining "$PLAN")
if [[ "$REMAINING" -eq 0 ]]; then
  echo "All tasks complete for '$FEATURE'."
  exit 0
fi

COMPLETED=$(ralph_count_completed "$PLAN")
TOTAL=$((COMPLETED + REMAINING))

echo "Ralph v$RALPH_VERSION — running feature: $FEATURE"
echo "Plan: $COMPLETED/$TOTAL tasks completed, $REMAINING remaining"
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
  REMAINING=$(ralph_count_remaining "$PLAN")
  if [[ "$REMAINING" -eq 0 ]]; then
    echo ""
    echo "All tasks complete!"
    break
  fi

  COMPLETED=$(ralph_count_completed "$PLAN")
  TOTAL=$((COMPLETED + REMAINING))

  echo "=== Iteration $i — Task $((COMPLETED + 1))/$TOTAL — $REMAINING remaining ==="

  # Execute claude (re-read prompt each time so mid-run edits take effect)
  claude -p "$(cat "$PROMPT")" --allowedTools "$RALPH_ALLOWED_TOOLS" $RALPH_CLAUDE_FLAGS \
    ${RALPH_PERMISSION_MODE:+--permission-mode "$RALPH_PERMISSION_MODE"} \
    ${RALPH_MCP_CONFIG:+--mcp-config "$RALPH_MCP_CONFIG"}
  EXIT_CODE=$?

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
REMAINING=$(ralph_count_remaining "$PLAN")
COMPLETED=$(ralph_count_completed "$PLAN")
TOTAL=$((COMPLETED + REMAINING))

if [[ "$REMAINING" -eq 0 ]]; then
  echo "Done — $TOTAL/$TOTAL tasks completed."
else
  echo "Stopped after $MAX_ITER iterations — $COMPLETED/$TOTAL tasks completed, $REMAINING remaining."
  exit 1
fi
