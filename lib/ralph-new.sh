#!/bin/bash
# ralph-new.sh — create a new feature directory with boilerplate

ralph_load_config

FEATURE_NAME=""
DESCRIPTION=""
NO_CLIPBOARD=false
USE_WORKTREE=false
BASE_BRANCH=""
BRANCH_TYPE="feat"

# Valid branch types
VALID_TYPES="feat fix chore hotfix release"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --description)
      DESCRIPTION="$2"
      shift 2 ;;
    --no-clipboard)
      NO_CLIPBOARD=true
      shift ;;
    --worktree)
      USE_WORKTREE=true
      shift ;;
    --base)
      BASE_BRANCH="$2"
      shift 2 ;;
    --type)
      BRANCH_TYPE="$2"
      shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: ralph new [name] [options]

Options:
  --description "..."   Feature description (interactive if omitted)
  --no-clipboard        Don't copy planning prompt to clipboard
  --worktree            Create feature in a new git worktree
  --base <branch>       Base branch for worktree (default: auto-detect)
  --type <prefix>       Branch prefix: feat, fix, chore, hotfix, release (default: feat)

Examples:
  ralph new my-feature
  ralph new my-feature --worktree
  ralph new my-feature --worktree --type fix --base develop
EOF
      exit 0 ;;
    -*)
      echo "Unknown option: $1"
      exit 1 ;;
    *)
      FEATURE_NAME="$1"
      shift ;;
  esac
done

# Get feature name interactively if not provided
if [[ -z "$FEATURE_NAME" ]]; then
  read -p "Feature name (kebab-case): " FEATURE_NAME
fi

ralph_validate_name "$FEATURE_NAME"

# Validate branch type
if [[ "$USE_WORKTREE" == true ]]; then
  if [[ ! " $VALID_TYPES " =~ " $BRANCH_TYPE " ]]; then
    echo "Error: Invalid branch type '$BRANCH_TYPE'"
    echo "Valid types: $VALID_TYPES"
    exit 1
  fi
fi

# Worktree setup
WORKTREE_PATH=""
WORKTREE_BRANCH=""
ORIGINAL_PROJECT_ROOT="$RALPH_PROJECT_ROOT"

if [[ "$USE_WORKTREE" == true ]]; then
  # Check we're in a git repository
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "Error: Not in a git repository"
    exit 1
  fi

  # Determine base branch
  if [[ -z "$BASE_BRANCH" ]]; then
    BASE_BRANCH="$(ralph_get_default_branch)"
    if [[ -z "$BASE_BRANCH" ]]; then
      echo "Error: Could not detect default branch. Use --base to specify."
      exit 1
    fi
  fi

  # Verify base branch exists
  if ! git show-ref --verify --quiet "refs/heads/$BASE_BRANCH" 2>/dev/null; then
    echo "Error: Base branch '$BASE_BRANCH' does not exist"
    exit 1
  fi

  WORKTREE_PATH="$(ralph_resolve_worktree_path "$FEATURE_NAME")"
  WORKTREE_BRANCH="$(ralph_resolve_branch_name "$FEATURE_NAME" "$BRANCH_TYPE")"

  # Check if worktree path already exists
  if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path already exists: $WORKTREE_PATH"
    exit 1
  fi

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$WORKTREE_BRANCH" 2>/dev/null; then
    echo "Error: Branch '$WORKTREE_BRANCH' already exists"
    exit 1
  fi

  # Create worktree base directory if needed
  mkdir -p "$(dirname "$WORKTREE_PATH")"

  # Create worktree with new branch
  if ! git worktree add "$WORKTREE_PATH" -b "$WORKTREE_BRANCH" "$BASE_BRANCH" 2>&1; then
    echo "Error: Failed to create worktree"
    exit 1
  fi

  echo "Created worktree: $WORKTREE_PATH"
  echo "Created branch: $WORKTREE_BRANCH (from $BASE_BRANCH)"

  # Update project root to the worktree for feature directory creation
  RALPH_PROJECT_ROOT="$WORKTREE_PATH"
fi

FEATURE_PATH="$RALPH_PROJECT_ROOT/$RALPH_FEATURE_DIR/$FEATURE_NAME"

# Check if feature already exists
if [[ -d "$FEATURE_PATH" ]] && [[ -n "$(ls -A "$FEATURE_PATH" 2>/dev/null)" ]]; then
  echo "Warning: Feature '$FEATURE_NAME' already exists. Existing files won't be overwritten."
fi

# Get description interactively if not provided
if [[ -z "$DESCRIPTION" ]]; then
  echo "Describe what you want to build (press Enter twice when done):"
  echo ""
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    DESCRIPTION+="$line"$'\n'
  done
fi

# Create directories
mkdir -p "$FEATURE_PATH"
mkdir -p "$FEATURE_PATH/references"

# Save description for later use by `ralph plan`
echo "$DESCRIPTION" > "$FEATURE_PATH/.description"

# Generate prompt.md from template
PROMPT_PATH="$FEATURE_PATH/$RALPH_PROMPT_FILE"
if [[ ! -f "$PROMPT_PATH" ]]; then
  # Resolve template: custom > built-in
  if [[ -n "$RALPH_PROMPT_TEMPLATE" ]] && [[ -f "$ORIGINAL_PROJECT_ROOT/$RALPH_PROMPT_TEMPLATE" ]]; then
    TEMPLATE="$ORIGINAL_PROJECT_ROOT/$RALPH_PROMPT_TEMPLATE"
  else
    TEMPLATE="$RALPH_ROOT/templates/prompt.md.tmpl"
  fi

  ralph_render_template "$TEMPLATE" "$FEATURE_NAME" > "$PROMPT_PATH"
  echo "Created: $RALPH_FEATURE_DIR/$FEATURE_NAME/$RALPH_PROMPT_FILE"
fi

FEATURE_DIR_REL="$RALPH_FEATURE_DIR/$FEATURE_NAME"

# Generate planning prompt
PLANNING_PROMPT="I want to build: $DESCRIPTION
Guide me through planning this. Ask me clarifying questions about:
- Scope and edge cases
- How it fits with existing patterns in this codebase
- UI/UX details I might not have thought of

Once we're aligned, generate:
1. $FEATURE_DIR_REL/$RALPH_SPEC_FILE
2. $FEATURE_DIR_REL/$RALPH_PLAN_FILE

Task sizing rules:
- Each task section = one ralph iteration = one full claude -p invocation (expensive!)
- Fewer, bigger tasks are better than many small ones. Don't create a task for a trivial change.
- Each task should touch multiple files or make a meaningful, testable chunk of progress
- Group related changes together (e.g., 'add model + service + view for X' is one task, not three)
- A single-file feature might be 1-2 tasks. A multi-system feature might be 5-10.
- Use checkbox format within each task for sub-steps:

## Task 1: Short description
- [ ] Sub-step A
- [ ] Sub-step B
- [ ] Sub-step C"

# Check for reference images
REF_DIR="$FEATURE_PATH/references"
REF_COUNT=$(find "$REF_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) 2>/dev/null | wc -l | tr -d ' ')
if [[ "$REF_COUNT" -gt 0 ]]; then
  PLANNING_PROMPT+="

Reference images are in $FEATURE_DIR_REL/references/ — examine them for design guidance."
fi

echo ""
echo "Created: $FEATURE_DIR_REL/"
echo "Created: $FEATURE_DIR_REL/references/ (drop screenshots/mockups here)"
echo ""

# Clipboard handling
if [[ "$USE_WORKTREE" == true ]]; then
  # For worktree mode, copy cd command
  CD_COMMAND="cd $WORKTREE_PATH"
  if [[ "$NO_CLIPBOARD" != true ]]; then
    if ralph_copy_to_clipboard "$CD_COMMAND"; then
      echo "cd command copied to clipboard."
      echo ""
    fi
  fi

  echo "Next steps:"
  echo "  $CD_COMMAND"
  echo "  # Plan your feature, then:"
  echo "  ralph run $FEATURE_NAME"
else
  # For non-worktree mode, copy planning prompt
  if [[ "$NO_CLIPBOARD" != true ]]; then
    if ralph_copy_to_clipboard "$PLANNING_PROMPT"; then
      echo "Planning prompt copied to clipboard."
      echo ""
    fi
  fi

  echo "Planning prompt:"
  echo "========================================"
  echo ""
  echo "$PLANNING_PROMPT"
  echo ""
  echo "========================================"
  echo ""
  echo "After planning is done, run:"
  echo "  ralph run $FEATURE_NAME"
fi
