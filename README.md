# Agent Coordinator

Git-based parallel AI agent coordinator. Workers with capabilities dynamically
claim tasks by priority. All coordination via a git `coordination` branch.

## Status

v0.1 — Local development only.

## Requirements

- Node.js 24+
- Git with worktree support
- Windows Terminal (`wt.exe`) for agent tabs

## Development

```bash
npm install
```

Quality gates run automatically via husky:

- **Pre-commit:** lint-staged auto-fixes formatting (prettier, shfmt, markdownlint)
- **Pre-push:** full test suite (`node --test`) + shellcheck
