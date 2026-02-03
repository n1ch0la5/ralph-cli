# Ralph CLI

Iterative AI-assisted feature development. A thin CLI wrapper around `claude -p` that breaks features into tasks and executes them one at a time.

## How It Works

1. **Plan** — describe a feature, collaborate with Claude to create a spec and task list
2. **Run** — ralph loops through tasks: invokes Claude, Claude implements one task, marks it done, repeat
3. **Track** — see progress across all features with `ralph status`

```
Planning/features/my-feature/
├── spec.md                    # What to build (created during planning)
├── implementation-plan.md     # Checkbox task list (created during planning)
├── prompt.md                  # Instructions for each Claude iteration
└── references/                # Screenshots, mockups, design references
```

## Install

**Homebrew (recommended):**

```bash
brew tap n1ch0la5/tap
brew install ralph-cli
```

**Clone + PATH:**

```bash
git clone https://github.com/n1ch0la5/ralph-cli.git ~/.ralph-cli
echo 'export PATH="$HOME/.ralph-cli/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Or with Make:**

```bash
git clone https://github.com/n1ch0la5/ralph-cli.git /tmp/ralph-cli
cd /tmp/ralph-cli && make install
```

## Quick Start

```bash
# In your project root
ralph init                     # creates .ralphrc with defaults

ralph new my-feature           # creates feature directory, copies planning prompt

# Paste the planning prompt into Claude Code (interactive session)
# Collaborate to produce spec.md and implementation-plan.md

ralph run my-feature           # executes the loop until all tasks are done
```

## Commands

### `ralph init`

Set up ralph in the current project. Creates `.ralphrc` with documented defaults and the feature directory.

```bash
ralph init [--force]
```

### `ralph new`

Create a new feature directory with `prompt.md` and a `references/` folder. Outputs a planning prompt (and copies it to clipboard on macOS).

```bash
ralph new [name] [--description "..."] [--no-clipboard]
ralph new [name] --worktree [--base <branch>] [--type <prefix>]
```

**Worktree mode** (`--worktree`) creates the feature in an isolated git worktree, keeping your main branch clean:

- `--worktree` — create feature in a new git worktree
- `--base <branch>` — base branch for the worktree (default: auto-detect main/master)
- `--type <prefix>` — branch prefix: `feat`, `fix`, `chore`, `hotfix`, `release` (default: `feat`)

```bash
# Creates worktree at ../worktrees/my-project/auth-flow
# with branch feat/auth-flow
ralph new auth-flow --worktree

# Create a bugfix worktree from develop branch
ralph new header-bug --worktree --type fix --base develop
```

The worktree path is copied to clipboard. cd into it and continue with planning.

### `ralph run`

Execute the iterative Claude loop. Reads `prompt.md`, invokes `claude -p`, checks for completed tasks, repeats.

```bash
ralph run <feature> [--max-iterations N] [--dry-run] [--no-sleep]
```

- `--dry-run` shows the claude command without executing
- `--no-sleep` skips the delay between iterations

### `ralph status`

Show progress for one feature or all features.

```bash
ralph status                   # all features with progress bars
ralph status my-feature        # detailed view of one feature
```

### `ralph plan`

Regenerate the planning prompt for an existing feature (useful if you lost it).

```bash
ralph plan <feature> [--clipboard]
```

### `ralph code-review`

Perform an AI-powered code review of all changes in a feature branch. Diffs the current branch against the base and sends the changes to Claude for analysis.

```bash
ralph code-review <feature> [--role <persona>] [--async] [--status]
```

- `--role <persona>` — explicit reviewer persona (e.g., "Senior Laravel Engineer")
- `--async` — run review in background, return immediately
- `--status` — check progress of an async review

The reviewer role is auto-detected from the codebase:
- Analyzes diff file extensions to determine dominant language
- Falls back to framework markers (composer.json, package.json, etc.)
- Supports PHP/Laravel, Python, TypeScript, JavaScript, Go, Rust, Ruby, Java

```bash
# Review a feature branch
ralph code-review my-feature

# Specify reviewer expertise
ralph code-review my-feature --role "Senior Laravel Engineer"

# Run in background and check status later
ralph code-review my-feature --async
ralph code-review --status my-feature
```

### `ralph worktree delete`

Remove a feature worktree created with `ralph new --worktree`.

```bash
ralph worktree delete <feature> [--with-branch] [--force] [--dry-run]
```

- `--with-branch` — also delete the local git branch
- `--force` — remove even if there are uncommitted changes
- `--dry-run` — show what would be removed without doing it

```bash
# Preview what would be removed
ralph worktree delete auth-flow --dry-run --with-branch

# Remove worktree and branch
ralph worktree delete auth-flow --with-branch
```

## Configuration

Create `.ralphrc` in your project root (`ralph init` does this). It's a shell-sourceable key=value file:

```bash
# Directory where feature plans are stored
RALPH_FEATURE_DIR="Planning/features"

# Tools Claude is allowed to use
RALPH_ALLOWED_TOOLS="Edit,Write,Bash,Read,Glob,Grep"

# Additional claude flags (e.g., --model opus)
RALPH_CLAUDE_FLAGS=""

# Permission mode (acceptEdits, bypassPermissions, etc.)
RALPH_PERMISSION_MODE=""

# Max iterations before stopping
RALPH_MAX_ITERATIONS=20

# Seconds between iterations
RALPH_SLEEP_SECONDS=2

# Git commit message prefix ({{FEATURE}} is replaced)
RALPH_COMMIT_PREFIX="[{{FEATURE}}]"

# Custom prompt template path (relative to project root)
RALPH_PROMPT_TEMPLATE=""

# MCP server config (for project-specific MCP servers)
RALPH_MCP_CONFIG=".mcp.json"

# Base directory for worktrees (relative to project root or absolute)
RALPH_WORKTREE_BASE="../worktrees"

# Code review: override auto-detected reviewer role
RALPH_CODE_REVIEW_ROLE="Senior Laravel Engineer"

# Code review: additional criteria (added to standard review)
RALPH_CODE_REVIEW_CRITERIA="accessibility,i18n"
```

See `.ralphrc.example` for all options with descriptions.

## MCP Servers

Projects that use MCP servers (Apple docs, database tools, etc.) can point ralph at a config file:

```bash
# .ralphrc
RALPH_MCP_CONFIG=".mcp.json"
```

This passes `--mcp-config .mcp.json` to every `claude -p` invocation. The config file follows the standard Claude Code MCP format.

## Reference Images

Drop screenshots, mockups, or design references into a feature's `references/` directory:

```
Planning/features/my-feature/references/
├── mockup.png
├── current-state.png
└── design-spec.pdf
```

The planning prompt and default iteration prompt both instruct Claude to examine reference images when present.

## Custom Prompts

Each feature has its own `prompt.md`. The default is generated from a template, but you can edit it freely. Common customizations:

- **Documentation tasks**: change instructions to "read source files and write markdown" instead of "implement code"
- **Refactoring tasks**: add constraints like "don't change public API"
- **Language-specific rules**: add file size limits, linting requirements, etc.

Project-wide rules belong in your `CLAUDE.md` (or equivalent). Ralph's default template tells Claude to read it.

## Requirements

- bash 4+
- `claude` CLI ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) installed and in PATH

## License

MIT
