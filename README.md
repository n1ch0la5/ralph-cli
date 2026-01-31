# ralph

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

**Clone + PATH (simplest):**

```bash
git clone https://github.com/youruser/ralph.git ~/Apps/cli/ralph
echo 'export PATH="$HOME/Apps/cli/ralph/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Or with Make:**

```bash
git clone https://github.com/youruser/ralph.git /tmp/ralph
cd /tmp/ralph && make install
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
```

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
- `claude` CLI (Claude Code) installed and in PATH

## License

MIT
