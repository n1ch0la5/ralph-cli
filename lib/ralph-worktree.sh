#!/bin/bash
# ralph-worktree.sh — manage git worktrees for ralph features

ralph_load_config

SUBCOMMAND="${1:-}"

ralph_worktree_usage() {
  cat <<USAGE
Usage: ralph worktree <subcommand> [options]

Subcommands:
  delete <feature>    Remove a feature worktree

Delete options:
  --with-branch       Also delete the local git branch
  --force             Remove even with uncommitted changes
  --dry-run           Show what would be removed without doing it

Examples:
  ralph worktree delete my-feature
  ralph worktree delete my-feature --with-branch
  ralph worktree delete my-feature --dry-run --with-branch
USAGE
}

ralph_worktree_delete() {
  local feature=""
  local with_branch=false
  local force=false
  local dry_run=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-branch)
        with_branch=true
        shift ;;
      --force)
        force=true
        shift ;;
      --dry-run)
        dry_run=true
        shift ;;
      --help|-h)
        cat <<HELP
Usage: ralph worktree delete <feature> [options]

Options:
  --with-branch    Also delete the local git branch
  --force          Remove even with uncommitted changes
  --dry-run        Show what would be removed without doing it

Examples:
  ralph worktree delete my-feature
  ralph worktree delete my-feature --with-branch
  ralph worktree delete my-feature --force --with-branch
HELP
        exit 0 ;;
      -*)
        echo "Unknown option: $1"
        exit 1 ;;
      *)
        feature="$1"
        shift ;;
    esac
  done

  # Validate feature name provided
  if [[ -z "$feature" ]]; then
    echo "Error: Feature name required"
    echo "Usage: ralph worktree delete <feature> [--with-branch] [--force] [--dry-run]"
    exit 1
  fi

  # Resolve worktree path
  local worktree_path
  worktree_path="$(ralph_resolve_worktree_path "$feature")"

  # Check worktree exists
  if [[ ! -d "$worktree_path" ]]; then
    echo "Error: Worktree does not exist: $worktree_path"
    exit 1
  fi

  # Find the branch name for this worktree
  local branch_name
  branch_name="$(ralph_find_worktree_branch "$worktree_path")"

  # Check for uncommitted changes
  if ralph_worktree_has_changes "$worktree_path"; then
    if [[ "$force" != true ]]; then
      echo "Error: Worktree has uncommitted changes: $worktree_path"
      echo "Use --force to remove anyway"
      exit 1
    fi
  fi

  # Handle dry-run
  if [[ "$dry_run" == true ]]; then
    echo "Dry run — no changes made."
    echo "Would remove worktree: $worktree_path"
    if [[ "$with_branch" == true ]] && [[ -n "$branch_name" ]]; then
      echo "Would delete branch: $branch_name (--with-branch specified)"
    fi
    exit 0
  fi

  # Remove worktree
  local remove_args=("$worktree_path")
  if [[ "$force" == true ]]; then
    remove_args=("--force" "$worktree_path")
  fi

  if ! git worktree remove "${remove_args[@]}" 2>&1; then
    echo "Error: Failed to remove worktree"
    exit 1
  fi

  echo "Removed worktree: $worktree_path"

  # Delete branch if requested
  if [[ "$with_branch" == true ]] && [[ -n "$branch_name" ]]; then
    local delete_flag="-d"
    if [[ "$force" == true ]]; then
      delete_flag="-D"
    fi

    if git branch "$delete_flag" "$branch_name" 2>&1; then
      echo "Deleted branch: $branch_name"
    else
      echo "Warning: Could not delete branch: $branch_name"
    fi
  fi
}

# Subcommand dispatch
case "$SUBCOMMAND" in
  delete)
    shift
    ralph_worktree_delete "$@"
    ;;
  help|--help|-h)
    ralph_worktree_usage
    exit 0
    ;;
  "")
    echo "Error: Subcommand required"
    ralph_worktree_usage
    exit 1
    ;;
  *)
    echo "Unknown subcommand: $SUBCOMMAND"
    ralph_worktree_usage
    exit 1
    ;;
esac
