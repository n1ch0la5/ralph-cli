#!/bin/bash
# ralph-init.sh — set up ralph in the current project

ralph_load_config

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *)
      echo "Usage: ralph init [--force]"
      exit 1 ;;
  esac
done

RC_FILE="$RALPH_PROJECT_ROOT/.ralphrc"

# Check for existing config
if [[ -f "$RC_FILE" ]] && [[ "$FORCE" != true ]]; then
  echo "Already initialized — .ralphrc exists at $RC_FILE"
  echo "Use --force to overwrite (current file backed up to .ralphrc.bak)"
  exit 1
fi

if [[ -f "$RC_FILE" ]] && [[ "$FORCE" == true ]]; then
  cp "$RC_FILE" "${RC_FILE}.bak"
  echo "Backed up existing .ralphrc to .ralphrc.bak"
fi

# Detect project type (informational only)
DETECTED=""
if [[ -f "$RALPH_PROJECT_ROOT/Package.swift" ]] || ls "$RALPH_PROJECT_ROOT"/*.xcodeproj &>/dev/null 2>&1; then
  DETECTED="Swift/iOS"
elif [[ -f "$RALPH_PROJECT_ROOT/package.json" ]]; then
  DETECTED="JavaScript/TypeScript"
elif [[ -f "$RALPH_PROJECT_ROOT/requirements.txt" ]] || [[ -f "$RALPH_PROJECT_ROOT/pyproject.toml" ]]; then
  DETECTED="Python"
elif [[ -f "$RALPH_PROJECT_ROOT/Cargo.toml" ]]; then
  DETECTED="Rust"
elif [[ -f "$RALPH_PROJECT_ROOT/go.mod" ]]; then
  DETECTED="Go"
fi

if [[ -n "$DETECTED" ]]; then
  echo "Detected project type: $DETECTED"
fi

# Write .ralphrc
cat > "$RC_FILE" << 'EOF'
# .ralphrc — Ralph configuration
# All values are optional. Uncomment and edit to override defaults.

# Directory where feature plans are stored (relative to project root)
# RALPH_FEATURE_DIR="Planning/features"

# Tools Claude is allowed to use during execution
# RALPH_ALLOWED_TOOLS="Edit,Write,Bash,Read,Glob,Grep"

# Additional flags passed to every `claude -p` invocation
# Example: --model opus --max-budget-usd 5
# RALPH_CLAUDE_FLAGS=""

# Permission mode for claude invocations
# Options: acceptEdits, bypassPermissions, default, plan
# RALPH_PERMISSION_MODE=""

# Maximum iterations before ralph gives up
# RALPH_MAX_ITERATIONS=20

# Seconds to sleep between iterations
# RALPH_SLEEP_SECONDS=2

# Whether prompts should include git commit instructions
# RALPH_GIT_COMMIT=true

# Git commit message prefix ({{FEATURE}} is replaced with feature name)
# RALPH_COMMIT_PREFIX="[{{FEATURE}}]"

# Path to a custom prompt template (relative to project root)
# If empty, uses ralph's built-in default template
# RALPH_PROMPT_TEMPLATE=""
EOF

echo "Created .ralphrc at $RC_FILE"

# Create feature directory
FEATURE_DIR="$RALPH_PROJECT_ROOT/$RALPH_FEATURE_DIR"
if [[ ! -d "$FEATURE_DIR" ]]; then
  mkdir -p "$FEATURE_DIR"
  echo "Created $RALPH_FEATURE_DIR/"
fi

echo ""
echo "Edit .ralphrc to customize. Run 'ralph new' to create your first feature."
