# Agent Coordinator

Git-based parallel AI agent coordinator. Workers with capabilities dynamically
claim tasks by priority. All coordination via a git `coordination` branch.

## Status

v0.1 — Local development only.

## Requirements

- Node.js 24+
- Git with worktree support
- Windows Terminal (`wt.exe`) for agent tabs

### Optional: Spec-Kit (for planning phase)

If you want to use `coordinator plan` for task generation:

```bash
# Install uv (Python package manager) if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Spec-Kit
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

Requires Python 3.11+.
See [github/spec-kit](https://github.com/github/spec-kit) for details.

## Usage

### 1. Initialize Coordinator

```bash
coordinator init
```

Creates `.coordination/` directory and `coordination` branch for task tracking.

### 2. Generate Tasks (with Spec-Kit)

If you have Spec-Kit installed and have created a `tasks.md`:

```bash
# Auto-discover tasks.md in specs/ directory
coordinator plan

# Or specify path explicitly
coordinator plan specs/001-my-feature/tasks.md
```

This converts Spec-Kit's markdown tasks to JSON files on the coordination branch.

### 3. Manually Create Tasks (without Spec-Kit)

Create JSON files directly on the coordination branch:

```bash
git checkout coordination
cat > tasks/001.json <<JSON
{
  "id": "001",
  "type": "implementation",
  "status": "pending",
  "description": "Implement user authentication",
  "acceptanceCriteria": ["User can log in", "Session persists"],
  "owns": ["src/auth/login.js"],
  "touches": [],
  "blockedBy": [],
  "claimedBy": null,
  "history": []
}
JSON
git add tasks/001.json
git commit -m "Add task 001"
git checkout main
```

See `.coordination/claude-md/planner.md` for the full task JSON schema.

### 4. Start Agents

```bash
coordinator start
```

Creates worktrees and launches agents in Windows Terminal tabs.

### 5. Monitor Progress

```bash
coordinator status
```

Shows which tasks are pending, claimed, or complete.

## Development

```bash
npm install
```

Quality gates run automatically via husky:

- **Pre-commit:** lint-staged auto-fixes formatting (prettier, shfmt, markdownlint)
- **Pre-push:** full test suite (`node --test`) + shellcheck
