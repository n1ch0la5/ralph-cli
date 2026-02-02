# Implementation Plan: Git Worktrees Integration

## Task 1: Foundation and `ralph new --worktree`

Add worktree configuration, helper functions, and implement the `--worktree` flag on `ralph new`.

- [x] Add `RALPH_WORKTREE_BASE` to defaults in `ralph_load_config()` in `lib/ralph-common.sh`
- [x] Add helper function `ralph_get_repo_name()` to extract repository name from project root
- [x] Add helper function `ralph_get_default_branch()` to auto-detect default branch with fallbacks
- [x] Add helper function `ralph_resolve_worktree_path()` to compute full worktree path from feature name
- [x] Add helper function `ralph_resolve_branch_name()` to compute branch name from feature and type
- [x] Update `ralph_usage()` in `lib/ralph-common.sh` to document the new `--worktree` flag and `worktree` command
- [x] Modify `lib/ralph-new.sh` to parse new flags: `--worktree`, `--base <branch>`, `--type <prefix>`
- [x] Modify `lib/ralph-new.sh` to validate `--type` value (feat, fix, chore, hotfix, release)
- [x] Implement worktree creation logic in `lib/ralph-new.sh`:
  - Check we're in a git repository
  - Check worktree path doesn't already exist
  - Check branch doesn't already exist
  - Create worktree base directory if needed
  - Run `git worktree add <path> -b <branch> <base>`
  - Create feature directory inside worktree (reuse existing logic)
  - Copy `cd <path>` to clipboard
  - Print success output with next steps
- [x] Update help text in `lib/ralph-new.sh` to show new flags

## Task 2: `ralph worktree delete` command

Create the worktree delete command with `--with-branch`, `--force`, and `--dry-run` flags.

- [x] Add case for `worktree` in `bin/ralph` dispatch (routes to `lib/ralph-worktree.sh`)
- [x] Create `lib/ralph-worktree.sh` with subcommand dispatch (currently only `delete`)
- [x] Implement argument parsing for `delete` subcommand: feature name, `--with-branch`, `--force`, `--dry-run`
- [x] Add helper function `ralph_worktree_has_changes()` in `lib/ralph-common.sh` to check for uncommitted changes
- [x] Add helper function `ralph_find_worktree_branch()` in `lib/ralph-common.sh` to find branch name for a worktree path
- [x] Implement delete logic:
  - Resolve worktree path from feature name
  - Check worktree exists
  - Check for uncommitted changes (error without `--force`)
  - Handle `--dry-run`: print what would be removed and exit
  - Run `git worktree remove <path>` (with `--force` if specified)
  - If `--with-branch`: run `git branch -d <branch>` (or `-D` if `--force`)
  - Print confirmation
- [x] Add help text for `ralph worktree delete`
- [x] Update `Makefile` to install `lib/ralph-worktree.sh` (not needed - Makefile uses `cp lib/*.sh` wildcard)
