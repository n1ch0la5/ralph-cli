#!/bin/bash
# ralph-common.sh — shared functions for all ralph commands

ralph_usage() {
  cat <<EOF
ralph $RALPH_VERSION — iterative AI-assisted feature development

Usage:
  ralph init                    Set up ralph in the current project
  ralph new [name]              Create a new feature directory
    --worktree                  Create feature in a new git worktree
    --base <branch>             Base branch for worktree (default: auto-detect)
    --type <prefix>             Branch prefix: feat, fix, chore, hotfix, release (default: feat)
  ralph run <feature>           Execute the iterative Claude loop
  ralph status [feature]        Show progress for one or all features
  ralph plan <feature>          Regenerate the planning prompt
  ralph worktree delete <name>  Remove a feature worktree
    --with-branch               Also delete the local git branch
    --force                     Remove even with uncommitted changes
    --dry-run                   Show what would be removed
  ralph version                 Print version
  ralph help                    Show this help

Configuration:
  Create a .ralphrc file in your project root (ralph init does this).
  See .ralphrc.example for all options.
EOF
}

# Find project root by walking up from cwd looking for .ralphrc or .git
# Note: .git is a directory in normal repos, but a file in worktrees
ralph_find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.ralphrc" ]] || [[ -d "$dir/.git" ]] || [[ -f "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$PWD"
}

# Load config: set defaults, then source .ralphrc if present
ralph_load_config() {
  RALPH_FEATURE_DIR="Planning/features"
  RALPH_ALLOWED_TOOLS="Edit,Write,Bash,Read,Glob,Grep"
  RALPH_CLAUDE_FLAGS=""
  RALPH_PERMISSION_MODE=""
  RALPH_MAX_ITERATIONS=20
  RALPH_SLEEP_SECONDS=2
  RALPH_GIT_COMMIT=true
  RALPH_COMMIT_PREFIX="[{{FEATURE}}]"
  RALPH_PROMPT_TEMPLATE=""
  RALPH_MCP_CONFIG=""
  RALPH_PLAN_FILE="implementation-plan.md"
  RALPH_SPEC_FILE="spec.md"
  RALPH_PROMPT_FILE="prompt.md"
  RALPH_WORKTREE_BASE="../worktrees"

  RALPH_PROJECT_ROOT="$(ralph_find_project_root)"

  if [[ -f "$RALPH_PROJECT_ROOT/.ralphrc" ]]; then
    source "$RALPH_PROJECT_ROOT/.ralphrc"
  fi
}

# Resolve absolute path to a feature directory
ralph_feature_path() {
  local feature="$1"
  echo "$RALPH_PROJECT_ROOT/$RALPH_FEATURE_DIR/$feature"
}

# Exit with error if file doesn't exist
ralph_require_file() {
  local path="$1"
  local label="${2:-$path}"
  if [[ ! -f "$path" ]]; then
    echo "Error: $label not found at $path"
    exit 1
  fi
}

# Count unchecked checkboxes in a plan file
ralph_count_remaining() {
  local count
  count=$(grep -c "^\- \[ \]" "$1" 2>/dev/null) || true
  echo "${count:-0}"
}

# Count completed checkboxes in a plan file
ralph_count_completed() {
  local count
  count=$(grep -c "^\- \[x\]" "$1" 2>/dev/null) || true
  echo "${count:-0}"
}

# Count task sections that still have unchecked items (## Task headers with remaining work)
ralph_count_sections_remaining() {
  local plan="$1"
  local count=0
  local in_section=false
  local section_has_unchecked=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Task ]]; then
      if [[ "$section_has_unchecked" == true ]]; then
        ((count++))
      fi
      in_section=true
      section_has_unchecked=false
    elif [[ "$in_section" == true ]] && [[ "$line" =~ ^-\ \[\ \] ]]; then
      section_has_unchecked=true
    fi
  done < "$plan"

  # Count the last section
  if [[ "$section_has_unchecked" == true ]]; then
    ((count++))
  fi

  echo "$count"
}

# Count total task sections (## Task headers)
ralph_count_sections_total() {
  local count
  count=$(grep -c "^## Task" "$1" 2>/dev/null) || true
  echo "${count:-0}"
}

# Render a template by substituting {{VAR}} placeholders
ralph_render_template() {
  local template="$1"
  local feature="$2"
  local feature_dir="$RALPH_FEATURE_DIR/$feature"
  local commit_prefix="${RALPH_COMMIT_PREFIX//\{\{FEATURE\}\}/$feature}"

  sed \
    -e "s|{{FEATURE}}|$feature|g" \
    -e "s|{{FEATURE_DIR}}|$feature_dir|g" \
    -e "s|{{SPEC_FILE}}|$RALPH_SPEC_FILE|g" \
    -e "s|{{PLAN_FILE}}|$RALPH_PLAN_FILE|g" \
    -e "s|{{PROMPT_FILE}}|$RALPH_PROMPT_FILE|g" \
    -e "s|{{COMMIT_PREFIX}}|$commit_prefix|g" \
    "$template"
}

# Copy text to clipboard (best-effort, silent failure)
ralph_copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy &>/dev/null; then
    echo "$text" | pbcopy
    return 0
  elif command -v xclip &>/dev/null; then
    echo "$text" | xclip -selection clipboard
    return 0
  elif command -v xsel &>/dev/null; then
    echo "$text" | xsel --clipboard
    return 0
  fi
  return 1
}

# Render a progress bar
ralph_progress_bar() {
  local completed=$1
  local total=$2
  local width=${3:-20}

  if [[ $total -eq 0 ]]; then
    printf '%*s' "$width" '' | tr ' ' '░'
    return
  fi

  local filled=$((completed * width / total))
  local empty=$((width - filled))

  local bar=""
  for ((j=0; j<filled; j++)); do bar+="█"; done
  for ((j=0; j<empty; j++)); do bar+="░"; done
  echo -n "$bar"
}

# Validate feature name (kebab-case)
ralph_validate_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z0-9]$ ]]; then
    echo "Error: Feature name must be kebab-case (lowercase letters, numbers, hyphens)"
    echo "  Example: my-feature, add-auth, fix-bug-123"
    exit 1
  fi
}

# Extract repository name from project root
ralph_get_repo_name() {
  basename "$RALPH_PROJECT_ROOT"
}

# Auto-detect the default branch with fallbacks
ralph_get_default_branch() {
  local branch

  # Try to get from origin HEAD
  branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [[ -n "$branch" ]]; then
    echo "$branch"
    return 0
  fi

  # Fallback: check if main exists
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo "main"
    return 0
  fi

  # Fallback: check if master exists
  if git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo "master"
    return 0
  fi

  return 1
}

# Compute full worktree path from feature name
ralph_resolve_worktree_path() {
  local feature="$1"
  local repo_name
  repo_name="$(ralph_get_repo_name)"

  local base="$RALPH_WORKTREE_BASE"

  # Resolve relative path from project root
  if [[ "$base" != /* ]]; then
    base="$RALPH_PROJECT_ROOT/$base"
  fi

  # Normalize the path
  echo "$(cd "$RALPH_PROJECT_ROOT" && cd "$(dirname "$base")" && pwd)/$(basename "$base")/$repo_name/$feature"
}

# Compute branch name from feature and type
ralph_resolve_branch_name() {
  local feature="$1"
  local type="${2:-feat}"
  echo "$type/$feature"
}

# Check if a worktree has uncommitted changes
ralph_worktree_has_changes() {
  local worktree_path="$1"
  local status
  status=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
  [[ -n "$status" ]]
}

# Find the branch name for a worktree path
ralph_find_worktree_branch() {
  local worktree_path="$1"
  # git worktree list --porcelain gives us structured output
  # Format: worktree <path>\nHEAD <sha>\nbranch <ref>\n\n
  git worktree list --porcelain | awk -v path="$worktree_path" '
    /^worktree / { current_path = substr($0, 10) }
    /^branch / && current_path == path { print substr($0, 8); exit }
  ' | sed 's@^refs/heads/@@'
}
