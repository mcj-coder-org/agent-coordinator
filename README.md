<!-- PORTFOLIO-BANNER:START -->
> **🗂️ Portfolio archive — Node.js CLI experiment (git-based multi-agent orchestration).** Part of a consolidated set of my personal repositories and **not actively maintained**.

<details>
<summary><b>📋 Self-review — 5 good practices &amp; 5 things I'd improve</b></summary>

**✅ Good practices demonstrated**
1. Honest, explicit status ("v0.1 — local development only") and stated requirements.
2. Quality gates wired from the start — Husky, lint-staged, Prettier, shellcheck, markdownlint.
3. Sensible layout (`bin` / `lib` / `tests`) with clear configuration.
4. `CLAUDE.md` documents the agent workflow and conventions.
5. Tooling foundation established before feature sprawl.

**⚠️ Weaknesses / what I'd do differently today**
1. Effectively a single-commit scaffold — no real iterative history.
2. The actual feature work sits in an unmerged PR (#1); the main branch is near-empty.
3. Hard dependency on Windows Terminal (`wt.exe`) limits portability.
4. No LICENSE.
5. A tests directory exists but coverage of the coordination logic is minimal.

</details>

---
<!-- PORTFOLIO-BANNER:END -->


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