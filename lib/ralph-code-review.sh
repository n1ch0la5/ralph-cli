#!/bin/bash
# ralph-code-review.sh — automated AI-powered code review for features

ralph_load_config

FEATURE=""
ROLE=""
ASYNC_MODE=false
STATUS_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="$2"
      shift 2 ;;
    --async)
      ASYNC_MODE=true
      shift ;;
    --status)
      STATUS_MODE=true
      shift ;;
    --help|-h)
      cat <<EOF
Usage: ralph code-review <feature> [options]

Perform an automated code review of all changes in a feature branch.

Options:
  --role <persona>    Explicit reviewer persona (e.g., "Senior Laravel Engineer")
  --async             Run review in background, return immediately
  --status            Check status of async review for specified feature
  --help              Show this help

Examples:
  ralph code-review my-feature
  ralph code-review my-feature --role "Senior Laravel Engineer"
  ralph code-review my-feature --async
  ralph code-review --status my-feature
EOF
      exit 0 ;;
    -*)
      echo "Unknown option: $1"
      exit 1 ;;
    *)
      FEATURE="$1"
      shift ;;
  esac
done

# Validate feature is provided (unless status mode without feature)
if [[ -z "$FEATURE" ]]; then
  echo "Usage: ralph code-review <feature> [--role <persona>] [--async]"
  echo "       ralph code-review --status <feature>"
  echo ""
  echo "Run 'ralph code-review --help' for more information."
  exit 1
fi

FEATURE_PATH="$(ralph_feature_path "$FEATURE")"

# Validate feature directory exists
if [[ ! -d "$FEATURE_PATH" ]]; then
  echo "Error: Feature '$FEATURE' not found."
  echo "Expected directory: $FEATURE_PATH"
  echo ""
  echo "Run 'ralph new $FEATURE' first to create the feature."
  exit 1
fi

# Handle status mode
if [[ "$STATUS_MODE" == true ]]; then
  ralph_code_review_status "$FEATURE" "$FEATURE_PATH"
  exit $?
fi

# Check for async review already running
PID_FILE="$FEATURE_PATH/.code-review.pid"
if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID=$(cat "$PID_FILE")
  if kill -0 "$EXISTING_PID" 2>/dev/null; then
    echo "Error: Review already in progress for '$FEATURE'."
    echo "Use 'ralph code-review --status $FEATURE' to check progress."
    exit 1
  else
    # Stale PID file, clean it up
    rm -f "$PID_FILE"
  fi
fi

# Determine base branch for diff
BASE_BRANCH=$(ralph_get_feature_base_branch)
if [[ -z "$BASE_BRANCH" ]]; then
  echo "Error: Cannot determine base branch for comparison."
  echo "Ensure 'main' or 'master' branch exists, or configure git remote."
  exit 1
fi

# Generate the diff
DIFF_OUTPUT=$(git diff "$BASE_BRANCH"...HEAD 2>/dev/null)
if [[ -z "$DIFF_OUTPUT" ]]; then
  echo "No changes found since base branch '$BASE_BRANCH'. Nothing to review."
  exit 0
fi

# Count files changed
FILES_CHANGED=$(git diff --name-only "$BASE_BRANCH"...HEAD | wc -l | tr -d ' ')

# Detect reviewer role
if [[ -z "$ROLE" ]]; then
  # Check config override
  if [[ -n "${RALPH_CODE_REVIEW_ROLE:-}" ]]; then
    ROLE="$RALPH_CODE_REVIEW_ROLE"
  else
    ROLE=$(ralph_detect_role "$BASE_BRANCH")
  fi
fi

# Read spec if it exists
SPEC_FILE="$FEATURE_PATH/$RALPH_SPEC_FILE"
SPEC_CONTENT=""
if [[ -f "$SPEC_FILE" ]]; then
  SPEC_CONTENT=$(cat "$SPEC_FILE")
fi

# Get additional review criteria from config
EXTRA_CRITERIA="${RALPH_CODE_REVIEW_CRITERIA:-}"

# Build the review prompt
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
REVIEW_PROMPT=$(ralph_build_code_review_prompt "$ROLE" "$DIFF_OUTPUT" "$SPEC_CONTENT" "$EXTRA_CRITERIA" "$BASE_BRANCH" "$FILES_CHANGED")

# Execute review (async or sync)
if [[ "$ASYNC_MODE" == true ]]; then
  ralph_code_review_async "$FEATURE" "$FEATURE_PATH" "$REVIEW_PROMPT" "$ROLE" "$BASE_BRANCH" "$FILES_CHANGED"
else
  ralph_code_review_sync "$FEATURE" "$FEATURE_PATH" "$REVIEW_PROMPT" "$ROLE" "$BASE_BRANCH" "$FILES_CHANGED"
fi
