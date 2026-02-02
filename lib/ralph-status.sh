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

  SECTIONS_TOTAL=0
  SECTIONS_REMAINING=0
  STEPS_COMPLETED=0
  STEPS_REMAINING=0

  if [[ -f "$PLAN" ]]; then
    SECTIONS_TOTAL=$(ralph_count_sections_total "$PLAN")
    SECTIONS_REMAINING=$(ralph_count_sections_remaining "$PLAN")
    STEPS_COMPLETED=$(ralph_count_completed "$PLAN")
    STEPS_REMAINING=$(ralph_count_remaining "$PLAN")
  fi

  SECTIONS_DONE=$((SECTIONS_TOTAL - SECTIONS_REMAINING))
  STEPS_TOTAL=$((STEPS_COMPLETED + STEPS_REMAINING))

  # Determine status
  if [[ $SECTIONS_TOTAL -eq 0 ]]; then
    STATUS="No Tasks"
  elif [[ $SECTIONS_REMAINING -eq 0 ]]; then
    STATUS="Complete"
  elif [[ $SECTIONS_DONE -eq 0 ]]; then
    STATUS="Not Started"
  else
    STATUS="In Progress"
  fi

  echo "Feature: $FEATURE"
  echo "Status:  $STATUS"
  echo ""

  if [[ $SECTIONS_TOTAL -gt 0 ]]; then
    echo "Sections:  $SECTIONS_DONE/$SECTIONS_TOTAL completed  (each section = 1 ralph iteration)"
    if [[ $STEPS_TOTAL -gt 0 ]]; then
      echo "Steps:     $STEPS_COMPLETED/$STEPS_TOTAL checkboxes ($((STEPS_COMPLETED * 100 / STEPS_TOTAL))%)"
    fi
    echo ""

    # Print task sections with their status
    if [[ -f "$PLAN" ]]; then
      current_section=""
      section_done=true
      while IFS= read -r line; do
        if [[ "$line" =~ ^##\ Task ]]; then
          # Print previous section before starting a new one
          if [[ -n "$current_section" ]]; then
            if [[ "$section_done" == true ]]; then
              echo "  ✓ $current_section"
            else
              echo "  ○ $current_section"
            fi
          fi
          current_section="$line"
          section_done=true
        elif [[ "$line" =~ ^-\ \[\ \] ]]; then
          section_done=false
        fi
      done < "$PLAN"
      # Print last section
      if [[ -n "$current_section" ]]; then
        if [[ "$section_done" == true ]]; then
          echo "  ✓ $current_section"
        else
          echo "  ○ $current_section"
        fi
      fi
    fi

    echo ""
  fi

  # Show action items if they exist
  ACTION_ITEMS="$FEATURE_PATH/action-items.md"
  if [[ -f "$ACTION_ITEMS" ]] && [[ -s "$ACTION_ITEMS" ]]; then
    echo "Action items:"
    while IFS= read -r line; do
      echo "  $line"
    done < "$ACTION_ITEMS"
    echo ""
  fi

  # Check which files exist
  echo "Files:"
  for fname in "$RALPH_SPEC_FILE" "$RALPH_PLAN_FILE" "$RALPH_PROMPT_FILE" "action-items.md"; do
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

  # Check for logs
  LOGS_DIR="$FEATURE_PATH/logs"
  if [[ -d "$LOGS_DIR" ]]; then
    LOG_COUNT=$(find "$LOGS_DIR" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$LOG_COUNT" -gt 0 ]]; then
      printf "  %-30s %s file(s)\n" "logs/" "$LOG_COUNT"
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

  sec_total=0
  sec_remaining=0

  if [[ -f "$plan" ]]; then
    sec_total=$(ralph_count_sections_total "$plan")
    sec_remaining=$(ralph_count_sections_remaining "$plan")
  fi

  sec_done=$((sec_total - sec_remaining))

  if [[ $sec_total -eq 0 ]]; then
    pct_label="no tasks"
    bar="$(ralph_progress_bar 0 1 20)"
  elif [[ $sec_remaining -eq 0 ]]; then
    pct_label="done"
    bar="$(ralph_progress_bar "$sec_total" "$sec_total" 20)"
  else
    pct="$((sec_done * 100 / sec_total))"
    pct_label="${pct}%"
    bar="$(ralph_progress_bar "$sec_done" "$sec_total" 20)"
  fi

  printf "  %-24s %2d/%-2d %s %s\n" "$name" "$sec_done" "$sec_total" "$bar" "$pct_label"
done

if [[ "$HAS_FEATURES" != true ]]; then
  echo "  (none)"
  echo ""
  echo "Run 'ralph new' to create your first feature."
fi
