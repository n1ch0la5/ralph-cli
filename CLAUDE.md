# Ralph CLI — Development Notes

## Project Structure

Bash CLI tool. Entry point is `bin/ralph`, which sources modules from `lib/`.
Prompt templates live in `templates/`. No build step.

## Releasing a New Version

### 1. Bump the version

Edit `bin/ralph` and update `RALPH_VERSION`:

```bash
RALPH_VERSION="0.X.Y"
```

Commit and push:

```bash
git add bin/ralph
git commit -m "Bump version to 0.X.Y"
git push origin main
```

### 2. Create and push a git tag

```bash
git tag v0.X.Y
git push origin v0.X.Y
```

### 3. Update the Homebrew tap formula

The tap lives at: https://github.com/n1ch0la5/homebrew-tap
Local checkout: `/opt/homebrew/Library/Taps/n1ch0la5/homebrew-tap`

First, get the sha256 of the new tag's tarball:

```bash
curl -sL https://github.com/n1ch0la5/ralph-cli/archive/refs/tags/v0.X.Y.tar.gz | shasum -a 256
```

Then edit the formula:

```bash
$EDITOR /opt/homebrew/Library/Taps/n1ch0la5/homebrew-tap/Formula/ralph-cli.rb
```

Update these two lines:

```ruby
url "https://github.com/n1ch0la5/ralph-cli/archive/refs/tags/v0.X.Y.tar.gz"
sha256 "<paste the sha256 hash from above>"
```

Commit and push the tap:

```bash
cd /opt/homebrew/Library/Taps/n1ch0la5/homebrew-tap
git add Formula/ralph-cli.rb
git commit -m "Update ralph-cli to v0.X.Y"
git push origin main
```

### 4. Verify

```bash
brew update
brew upgrade ralph-cli
ralph version
```

## Feature Directory Layout

Each feature lives under `Planning/features/<name>/`:

```
spec.md                  # Requirements (created during planning)
implementation-plan.md   # Checkbox task list (tracks progress)
prompt.md                # Instructions for each Claude iteration
action-items.md          # Manual post-implementation steps (created by Claude)
followup-prompt.md       # Clipboard-ready prompt for continuing work
.description             # Original feature description
references/              # Screenshots, mockups
logs/                    # Saved output from each iteration (section-N.md)
```
