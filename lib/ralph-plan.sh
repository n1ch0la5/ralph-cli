#!/bin/bash
# ralph-plan.sh — regenerate and display the planning prompt for a feature

ralph_load_config

FEATURE=""
CLIPBOARD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clipboard|-c)
      CLIPBOARD=true
      shift ;;
    --help|-h)
      echo "Usage: ralph plan <feature> [--clipboard]"
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
  echo "Usage: ralph plan <feature> [--clipboard]"
  exit 1
fi

FEATURE_PATH="$(ralph_feature_path "$FEATURE")"

if [[ ! -d "$FEATURE_PATH" ]]; then
  echo "Feature '$FEATURE' not found."
  echo "Run 'ralph new $FEATURE' to create it."
  exit 1
fi

# Load description
DESCRIPTION=""
if [[ -f "$FEATURE_PATH/.description" ]]; then
  DESCRIPTION="$(cat "$FEATURE_PATH/.description")"
fi

if [[ -z "$DESCRIPTION" ]]; then
  echo "No .description file found for '$FEATURE'."
  echo "Enter a description (press Enter twice when done):"
  echo ""
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    DESCRIPTION+="$line"$'\n'
  done
  echo "$DESCRIPTION" > "$FEATURE_PATH/.description"
fi

FEATURE_DIR_REL="$RALPH_FEATURE_DIR/$FEATURE"

PLANNING_PROMPT="I want to build: $DESCRIPTION
Guide me through planning this. Ask me clarifying questions about:
- Scope and edge cases
- How it fits with existing patterns in this codebase
- UI/UX details I might not have thought of

Once we're aligned, generate:
1. $FEATURE_DIR_REL/$RALPH_SPEC_FILE
2. $FEATURE_DIR_REL/$RALPH_PLAN_FILE

Break tasks down so each completes in <15k tokens. Use checkbox format:
- [ ] Task description"

# Check for reference images
REF_DIR="$FEATURE_PATH/references"
REF_COUNT=$(find "$REF_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) 2>/dev/null | wc -l | tr -d ' ')
if [[ "$REF_COUNT" -gt 0 ]]; then
  PLANNING_PROMPT+="

Reference images are in $FEATURE_DIR_REL/references/ — examine them for design guidance."
fi

echo "$PLANNING_PROMPT"

if [[ "$CLIPBOARD" == true ]]; then
  if ralph_copy_to_clipboard "$PLANNING_PROMPT"; then
    echo ""
    echo "(Copied to clipboard)"
  fi
fi
