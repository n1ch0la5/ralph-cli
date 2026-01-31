#!/bin/bash
# ralph-status.sh — show progress for one or all features

ralph_load_config

FEATURE="${1:-}"
FEATURE_DIR="$RALPH_PROJECT_ROOT/$RALPH_FEATURE_DIR"

# Single feature mode
if [[ -n "$FEATURE" ]]; then
  FEATURE_PATH="$(ralph_feature_path "$FEATURE")"
  PLAN="$FEATURE_PATH/$RALPH_PLAN_FILE"

  if [[ ! -d "$FEATURE_PATH" ]]; then
    echo "Feature '$FEATURE' not found at $FEATURE_PATH"
    exit 1
  fi

  REMAINING=0
  COMPLETED=0

  if [[ -f "$PLAN" ]]; then
    REMAINING=$(ralph_count_remaining "$PLAN")
    COMPLETED=$(ralph_count_completed "$PLAN")
  fi

  TOTAL=$((COMPLETED + REMAINING))

  # Determine status
  if [[ $TOTAL -eq 0 ]]; then
    STATUS="No Tasks"
  elif [[ $REMAINING -eq 0 ]]; then
    STATUS="Complete"
  elif [[ $COMPLETED -eq 0 ]]; then
    STATUS="Not Started"
  else
    STATUS="In Progress"
  fi

  echo "Feature: $FEATURE"
  echo "Status:  $STATUS"
  echo ""

  if [[ $TOTAL -gt 0 ]]; then
    echo "Tasks: $COMPLETED/$TOTAL completed ($((COMPLETED * 100 / TOTAL))%)"
    echo ""

    # Print individual tasks
    if [[ -f "$PLAN" ]]; then
      grep -E "^\- \[(x| )\]" "$PLAN" | while IFS= read -r line; do
        echo "  $line"
      done
    fi

    echo ""
  fi

  # Check which files exist
  echo "Files:"
  for fname in "$RALPH_SPEC_FILE" "$RALPH_PLAN_FILE" "$RALPH_PROMPT_FILE"; do
    if [[ -f "$FEATURE_PATH/$fname" ]]; then
      printf "  %-30s ✓\n" "$fname"
    else
      printf "  %-30s ✗\n" "$fname"
    fi
  done

  # Check for references
  REF_DIR="$FEATURE_PATH/references"
  if [[ -d "$REF_DIR" ]]; then
    REF_COUNT=$(find "$REF_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$REF_COUNT" -gt 0 ]]; then
      printf "  %-30s %s file(s)\n" "references/" "$REF_COUNT"
    fi
  fi

  exit 0
fi

# All features mode
if [[ ! -d "$FEATURE_DIR" ]]; then
  echo "No features directory found at $RALPH_FEATURE_DIR/"
  echo "Run 'ralph init' to set up this project."
  exit 1
fi

echo "Features in $RALPH_FEATURE_DIR/:"
echo ""

# Collect features and sort by status
HAS_FEATURES=false
for dir in "$FEATURE_DIR"/*/; do
  [[ ! -d "$dir" ]] && continue
  HAS_FEATURES=true

  name="$(basename "$dir")"
  plan="$dir/$RALPH_PLAN_FILE"

  completed=0
  remaining=0

  if [[ -f "$plan" ]]; then
    completed=$(ralph_count_completed "$plan")
    remaining=$(ralph_count_remaining "$plan")
  fi

  total=$((completed + remaining))

  if [[ $total -eq 0 ]]; then
    pct_label="no tasks"
    bar="$(ralph_progress_bar 0 1 20)"
  elif [[ $remaining -eq 0 ]]; then
    pct_label="done"
    bar="$(ralph_progress_bar "$total" "$total" 20)"
  else
    pct="$((completed * 100 / total))"
    pct_label="${pct}%"
    bar="$(ralph_progress_bar "$completed" "$total" 20)"
  fi

  printf "  %-24s %2d/%-2d %s %s\n" "$name" "$completed" "$total" "$bar" "$pct_label"
done

if [[ "$HAS_FEATURES" != true ]]; then
  echo "  (none)"
  echo ""
  echo "Run 'ralph new' to create your first feature."
fi
