# Git Worktrees Integration

## Overview

Add git worktree support to ralph to enable isolated feature development. This prevents feature planning files and implementation work from polluting the user's current working branch, and allows users to context-switch (e.g., checkout a different branch in the main repo) while ralph runs in an isolated worktree.

## User Stories

1. **As a developer**, I want to start a new feature in an isolated worktree so that my main branch stays clean and I can switch contexts without interrupting ralph.

2. **As a developer**, I want to clean up worktrees when I'm done with a feature, optionally deleting the associated branch.

## Commands & Flags

### `ralph new <feature> --worktree`

Creates a new feature with an isolated git worktree.

**New flags:**
| Flag | Description | Default |
|------|-------------|---------|
| `--worktree` | Create feature in a new git worktree | (disabled) |
| `--base <branch>` | Base branch for the worktree | Auto-detect default branch |
| `--type <prefix>` | Branch prefix: `feat`, `fix`, `chore`, `hotfix`, `release` | `feat` |

**Behavior:**
1. Validate feature name (existing kebab-case validation)
2. Auto-detect repo's default branch (or use `--base`)
3. Create worktree at `RALPH_WORKTREE_BASE/<repo-name>/<feature>`
4. Create branch `<type>/<feature>` from base branch
5. Create feature directory inside the worktree (same as normal `ralph new`)
6. Copy `cd <worktree-path>` to clipboard
7. Print worktree path, branch name, and next steps

**Error conditions:**
- Worktree path already exists → error with message
- Branch already exists → error with message
- Not in a git repository → error with message

### `ralph worktree delete <feature>`

Removes a worktree created by ralph.

**Flags:**
| Flag | Description |
|------|-------------|
| `--with-branch` | Also delete the local git branch |
| `--force` | Remove even if there are uncommitted changes |
| `--dry-run` | Show what would be removed without doing it |

**Behavior:**
1. Resolve worktree path from feature name
2. Check for uncommitted changes in worktree
   - If changes exist and no `--force`: error with hint
3. If `--dry-run`: print what would be removed and exit
4. Run `git worktree remove <path>` (add `--force` if specified)
5. If `--with-branch`: run `git branch -d <branch>` (or `-D` if `--force`)
6. Print confirmation

**Error conditions:**
- Worktree doesn't exist → error with message
- Uncommitted changes without `--force` → error with hint to use `--force`

## Configuration

### New `.ralphrc` variable

```bash
RALPH_WORKTREE_BASE="../worktrees"
```

**Resolution:**
- If relative path: resolved relative to project root
- Default: `../worktrees` (sibling to project root)
- Full worktree path: `<RALPH_WORKTREE_BASE>/<repo-name>/<feature>`

Example: If project is at `/code/ralph-cli` and feature is `my-feature`:
- Worktree: `/code/worktrees/ralph-cli/my-feature`
- Branch: `feat/my-feature`

## Branch Naming

Follows [Conventional Branch](https://conventional-branch.github.io/) naming:

| Type | Example | Use case |
|------|---------|----------|
| `feat` | `feat/my-feature` | New features (default) |
| `fix` | `fix/header-bug` | Bug fixes |
| `chore` | `chore/update-deps` | Maintenance tasks |
| `hotfix` | `hotfix/security-patch` | Urgent fixes |
| `release` | `release/v1.2.0` | Release preparation |

## Output & UX

### `ralph new --worktree` success output

```
Created worktree: /code/worktrees/ralph-cli/my-feature
Created branch: feat/my-feature (from main)
Created: Planning/features/my-feature/
Created: Planning/features/my-feature/references/

cd command copied to clipboard.

Next steps:
  cd /code/worktrees/ralph-cli/my-feature
  # Plan your feature, then:
  ralph run my-feature
```

### `ralph worktree delete --dry-run` output

```
Dry run — no changes made.
Would remove worktree: /code/worktrees/ralph-cli/my-feature
Would delete branch: feat/my-feature (--with-branch specified)
```

### `ralph worktree delete` success output

```
Removed worktree: /code/worktrees/ralph-cli/my-feature
Deleted branch: feat/my-feature
```

## Auto-detecting Default Branch

Use git to determine the default branch:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Fallback order if that fails:
1. Check if `main` branch exists
2. Check if `master` branch exists
3. Error: "Could not detect default branch. Use --base to specify."

## Future Expansion (Not in Scope)

These may be added in future iterations:
- `ralph run --worktree` - create worktree if needed and run inside it
- `--dry-run` file/directory count for delete command
- `ralph worktree list` - list ralph-created worktrees (if `git worktree list` proves insufficient)
