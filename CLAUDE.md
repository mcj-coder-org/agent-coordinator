# Agent Coordinator

## Project Overview

Git-based CLI tool for coordinating parallel AI coding agents.
Bash core + Node.js for task logic. Zero production dependencies.

## Development

- `npm test` — run all tests
- `npm run lint:sh` — shellcheck all bash scripts

## Architecture

- `bin/coordinator.sh` — CLI entrypoint, dispatches subcommands
- `bin/agent-loop.sh` — per-agent process loop
- `lib/tasks.js` — task CRUD, dependency checking, claiming
- `lib/prompt-builder.js` — build prompts from task JSON + CLAUDE.md
- `tests/` — tests using `node:test` built-in

## Conventions

- Bash scripts: use `set -euo pipefail`, quote all variables
- Node.js: no external dependencies, use only built-ins
- Tests: use `node:test` and `node:assert`
- All functions must be tested before implementation is considered complete
