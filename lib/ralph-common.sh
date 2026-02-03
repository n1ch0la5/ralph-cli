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
  ralph code-review <feature>   Perform AI-powered code review
    --role <persona>            Explicit reviewer persona (e.g., "Senior Laravel Engineer")
    --async                     Run review in background, return immediately
    --status                    Check status of async review for specified feature
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

# Find the main repo root when in a worktree
# Returns the main repo root if in a worktree, otherwise returns the project root
ralph_find_main_repo_root() {
  local git_dir="$PWD/.git"

  # Check if .git is a file (worktree) rather than a directory (main repo)
  if [[ -f "$git_dir" ]]; then
    # .git file contains: gitdir: /path/to/main/.git/worktrees/name
    local gitdir
    gitdir=$(cat "$git_dir" | sed 's/^gitdir: //')
    # Extract main repo .git path: /path/to/main/.git/worktrees/name -> /path/to/main/.git
    local main_git="${gitdir%/worktrees/*}"
    # Return the repo root (parent of .git)
    echo "${main_git%/.git}"
  else
    # Not a worktree, return project root
    echo "$RALPH_PROJECT_ROOT"
  fi
}

# Detect reviewer role based on codebase technology stack
# Priority: diff file extensions > framework markers > default
ralph_detect_role() {
  local base_branch="${1:-main}"
  local role=""

  # Check diff file extensions
  local diff_files
  diff_files=$(git diff --name-only "$base_branch"...HEAD 2>/dev/null || echo "")

  if [[ -n "$diff_files" ]]; then
    # Count file types in the diff
    local php_count=$(echo "$diff_files" | grep -c '\.php$' || true)
    local py_count=$(echo "$diff_files" | grep -c '\.py$' || true)
    local ts_count=$(echo "$diff_files" | grep -cE '\.(ts|tsx)$' || true)
    local js_count=$(echo "$diff_files" | grep -cE '\.(js|jsx)$' || true)
    local go_count=$(echo "$diff_files" | grep -c '\.go$' || true)
    local rs_count=$(echo "$diff_files" | grep -c '\.rs$' || true)
    local rb_count=$(echo "$diff_files" | grep -c '\.rb$' || true)
    local java_count=$(echo "$diff_files" | grep -c '\.java$' || true)

    # Find dominant file type
    local max_count=0
    local dominant=""

    if [[ $php_count -gt $max_count ]]; then max_count=$php_count; dominant="php"; fi
    if [[ $py_count -gt $max_count ]]; then max_count=$py_count; dominant="python"; fi
    if [[ $ts_count -gt $max_count ]]; then max_count=$ts_count; dominant="typescript"; fi
    if [[ $js_count -gt $max_count ]]; then max_count=$js_count; dominant="javascript"; fi
    if [[ $go_count -gt $max_count ]]; then max_count=$go_count; dominant="go"; fi
    if [[ $rs_count -gt $max_count ]]; then max_count=$rs_count; dominant="rust"; fi
    if [[ $rb_count -gt $max_count ]]; then max_count=$rb_count; dominant="ruby"; fi
    if [[ $java_count -gt $max_count ]]; then max_count=$java_count; dominant="java"; fi

    if [[ -n "$dominant" ]]; then
      case "$dominant" in
        php)
          # Check for Laravel specifically
          if [[ -f "composer.json" ]] && grep -q "laravel/framework" "composer.json" 2>/dev/null; then
            role="Senior Laravel Engineer"
          else
            role="Senior PHP Engineer"
          fi
          ;;
        python) role="Senior Python Engineer" ;;
        typescript) role="Senior TypeScript Engineer" ;;
        javascript) role="Senior JavaScript Engineer" ;;
        go) role="Senior Go Engineer" ;;
        rust) role="Senior Rust Engineer" ;;
        ruby) role="Senior Ruby Engineer" ;;
        java) role="Senior Java Engineer" ;;
      esac
    fi
  fi

  # Fallback: check framework markers in project root
  if [[ -z "$role" ]]; then
    if [[ -f "composer.json" ]]; then
      if grep -q "laravel/framework" "composer.json" 2>/dev/null; then
        role="Senior Laravel Engineer"
      else
        role="Senior PHP Engineer"
      fi
    elif [[ -f "package.json" ]]; then
      if grep -q '"typescript"' "package.json" 2>/dev/null; then
        role="Senior TypeScript Engineer"
      else
        role="Senior JavaScript Engineer"
      fi
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
      role="Senior Python Engineer"
    elif [[ -f "Cargo.toml" ]]; then
      role="Senior Rust Engineer"
    elif [[ -f "go.mod" ]]; then
      role="Senior Go Engineer"
    elif [[ -f "Gemfile" ]]; then
      role="Senior Ruby Engineer"
    fi
  fi

  # Default fallback
  if [[ -z "$role" ]]; then
    role="Senior Software Engineer"
  fi

  echo "$role"
}

# Get the base branch for a feature (for diff comparison)
# Uses existing ralph_get_default_branch as it implements the same logic
ralph_get_feature_base_branch() {
  ralph_get_default_branch
}

# Build the code review prompt from template
ralph_build_code_review_prompt() {
  local role="$1"
  local diff="$2"
  local spec="$3"
  local extra_criteria="$4"
  local base_branch="$5"
  local files_changed="$6"

  local template_file="$RALPH_ROOT/templates/code-review-prompt.md.tmpl"

  if [[ ! -f "$template_file" ]]; then
    echo "Error: Code review prompt template not found at $template_file" >&2
    exit 1
  fi

  # Build criteria section
  local criteria_section=""
  if [[ -n "$extra_criteria" ]]; then
    criteria_section="

### Additional Review Criteria
$(echo "$extra_criteria" | tr ',' '\n' | sed 's/^/- /')"
  fi

  # Build spec section
  local spec_section=""
  if [[ -n "$spec" ]]; then
    spec_section="

### Feature Specification
\`\`\`markdown
$spec
\`\`\`"
  fi

  # Read template and substitute placeholders
  local prompt
  prompt=$(cat "$template_file")
  prompt="${prompt//\{\{ROLE\}\}/$role}"
  prompt="${prompt//\{\{BASE_BRANCH\}\}/$base_branch}"
  prompt="${prompt//\{\{FILES_CHANGED\}\}/$files_changed}"
  prompt="${prompt//\{\{EXTRA_CRITERIA\}\}/$criteria_section}"
  prompt="${prompt//\{\{SPEC_SECTION\}\}/$spec_section}"

  # Append the diff at the end
  prompt="$prompt

## Code Diff

\`\`\`diff
$diff
\`\`\`"

  echo "$prompt"
}

# Execute synchronous code review
ralph_code_review_sync() {
  local feature="$1"
  local feature_path="$2"
  local prompt="$3"
  local role="$4"
  local base_branch="$5"
  local files_changed="$6"

  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local output_file="$feature_path/code-review.md"

  echo "Ralph v$RALPH_VERSION — Code Review"
  echo "Feature: $feature"
  echo "Reviewer: $role"
  echo "Base branch: $base_branch"
  echo "Files changed: $files_changed"
  echo ""
  echo "Starting review..."
  echo ""

  # Create temp file for claude output
  local temp_output
  temp_output=$(mktemp)

  # Execute claude and capture output
  if claude -p "$prompt" --allowedTools "$RALPH_ALLOWED_TOOLS" $RALPH_CLAUDE_FLAGS \
    ${RALPH_PERMISSION_MODE:+--permission-mode "$RALPH_PERMISSION_MODE"} \
    ${RALPH_MCP_CONFIG:+--mcp-config "$RALPH_MCP_CONFIG"} > "$temp_output" 2>&1; then

    # Build the review section
    local review_section="## Code Review — $timestamp

**Reviewer Role:** $role
**Base Branch:** $base_branch
**Files Reviewed:** $files_changed

$(cat "$temp_output")

---
"

    # Append to code-review.md (create if doesn't exist)
    if [[ -f "$output_file" ]]; then
      echo "" >> "$output_file"
    fi
    echo "$review_section" >> "$output_file"

    # Display output to terminal
    cat "$temp_output"

    echo ""
    echo "Review saved to: $output_file"

    rm -f "$temp_output"
    return 0
  else
    local exit_code=$?
    echo "Error: Code review failed with exit code $exit_code"
    echo ""
    echo "Output:"
    cat "$temp_output"
    rm -f "$temp_output"
    return $exit_code
  fi
}

# Execute asynchronous code review
ralph_code_review_async() {
  local feature="$1"
  local feature_path="$2"
  local prompt="$3"
  local role="$4"
  local base_branch="$5"
  local files_changed="$6"

  local timestamp=$(date '+%Y-%m-%d_%H%M%S')
  local logs_dir="$feature_path/logs"
  local log_file="$logs_dir/code-review-$timestamp.log"
  local pid_file="$feature_path/.code-review.pid"
  local output_file="$feature_path/code-review.md"

  mkdir -p "$logs_dir"

  echo "Ralph v$RALPH_VERSION — Code Review (Async)"
  echo "Feature: $feature"
  echo "Reviewer: $role"
  echo "Base branch: $base_branch"
  echo "Files changed: $files_changed"
  echo ""

  # Start background process
  (
    local review_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Execute claude and capture output
    local temp_output
    temp_output=$(mktemp)

    claude -p "$prompt" --allowedTools "$RALPH_ALLOWED_TOOLS" $RALPH_CLAUDE_FLAGS \
      ${RALPH_PERMISSION_MODE:+--permission-mode "$RALPH_PERMISSION_MODE"} \
      ${RALPH_MCP_CONFIG:+--mcp-config "$RALPH_MCP_CONFIG"} > "$temp_output" 2>&1
    local claude_exit_code=$?

    if [[ $claude_exit_code -eq 0 ]]; then
      # Build the review section
      local review_section="## Code Review — $review_timestamp

**Reviewer Role:** $role
**Base Branch:** $base_branch
**Files Reviewed:** $files_changed

$(cat "$temp_output")

---
"

      # Append to code-review.md
      if [[ -f "$output_file" ]]; then
        echo "" >> "$output_file"
      fi
      echo "$review_section" >> "$output_file"

      # Also save to log file
      echo "Review completed at $(date '+%Y-%m-%d %H:%M:%S')" > "$log_file"
      echo "Output saved to: $output_file" >> "$log_file"
      echo "" >> "$log_file"
      cat "$temp_output" >> "$log_file"
    else
      echo "Review failed at $(date '+%Y-%m-%d %H:%M:%S')" > "$log_file"
      echo "Exit code: $claude_exit_code" >> "$log_file"
      echo "" >> "$log_file"
      cat "$temp_output" >> "$log_file"
    fi

    rm -f "$temp_output"
    rm -f "$pid_file"
  ) &

  # Save PID
  local bg_pid=$!
  echo "$bg_pid" > "$pid_file"

  echo "Review started in background (PID: $bg_pid)"
  echo "Log file: $log_file"
  echo ""
  echo "Check status with: ralph code-review --status $feature"
}

# Check status of async code review
ralph_code_review_status() {
  local feature="$1"
  local feature_path="$2"

  local pid_file="$feature_path/.code-review.pid"
  local output_file="$feature_path/code-review.md"
  local logs_dir="$feature_path/logs"

  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
      # Process is still running
      local start_time
      # Use modification time: %m on BSD/macOS, %Y on GNU/Linux
      start_time=$(stat -f %m "$pid_file" 2>/dev/null || stat -c %Y "$pid_file" 2>/dev/null)
      local now=$(date +%s)
      local elapsed=$((now - start_time))
      local minutes=$((elapsed / 60))
      local seconds=$((elapsed % 60))

      echo "Status: Running"
      echo "PID: $pid"
      echo "Elapsed: ${minutes}m ${seconds}s"
      echo ""
      echo "Waiting for review to complete..."
      return 0
    else
      # Process finished, clean up PID file
      rm -f "$pid_file"

      # Find the most recent log file
      local latest_log
      latest_log=$(ls -t "$logs_dir"/code-review-*.log 2>/dev/null | head -1)

      if [[ -n "$latest_log" ]] && grep -q "Review completed" "$latest_log" 2>/dev/null; then
        echo "Status: Complete"
        echo "Results: $output_file"
        echo "Log: $latest_log"
        return 0
      else
        echo "Status: Failed"
        if [[ -n "$latest_log" ]]; then
          echo "Log: $latest_log"
          echo ""
          echo "Error details:"
          cat "$latest_log"
        fi
        return 1
      fi
    fi
  else
    # No PID file - check if there are any completed reviews
    if [[ -f "$output_file" ]]; then
      echo "Status: No review in progress"
      echo "Previous reviews: $output_file"
    else
      echo "Status: Not started"
      echo "No code review has been run for '$feature'."
      echo ""
      echo "Start a review with: ralph code-review $feature"
    fi
    return 0
  fi
}
