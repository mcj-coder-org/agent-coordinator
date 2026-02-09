#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

usage() {
  cat <<'EOF'
Usage: coordinator <command> [options]

Commands:
  init          Initialize .coordination/ in current project
  start         Create worktrees and start agent loops
  stop          Stop agent loops and optionally clean worktrees
  add-agent     Spin up an additional agent
  status        Show current task and agent status
  plan          Run planner agent with Spec-Kit

Options:
  -h, --help    Show this help message
EOF
}

cmd_status() {
  local coord_dir=".coordination"
  if [[ ! -d "$coord_dir" ]]; then
    echo "Error: .coordination/ not found. Run 'coordinator init' first." >&2
    exit 1
  fi

  echo "=== Agent Coordinator Status ==="
  echo ""

  # Read tasks from coordination worktree
  local tasks_dir
  tasks_dir=$(git worktree list | grep "coordination" | awk '{print $1}')/tasks

  if [[ -d "$tasks_dir" ]]; then
    echo "Tasks:"
    for task_file in "$tasks_dir"/*.json; do
      [[ -f "$task_file" ]] || continue
      local id status type claimedBy
      id=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).id)")
      status=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).status)")
      type=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).type)")
      claimedBy=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).claimedBy || 'none')")
      printf "  %-6s %-15s %-20s agent: %s\n" "$id" "[$status]" "$type" "$claimedBy"
    done
  else
    echo "No tasks found."
  fi
}

cmd_init() {
  local coord_dir=".coordination"
  local templates_dir="$SCRIPT_DIR/../templates/coordination"

  if [[ -d "$coord_dir" ]]; then
    echo "Error: .coordination/ already exists." >&2
    exit 1
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  echo "Initializing .coordination/..."

  # Copy templates
  cp -r "$templates_dir" "$coord_dir"
  echo "  Created .coordination/ with config and CLAUDE.md templates"

  # Create coordination orphan branch
  local current_branch
  current_branch=$(git branch --show-current)
  git checkout --orphan coordination
  git rm -rf . >/dev/null 2>&1 || true
  mkdir -p tasks
  cat >README.md <<'HEREDOC'
# Coordination Branch

This branch holds task JSON files for agent coordination.
It is never merged to main.
HEREDOC
  git add tasks README.md
  git commit -m "init: coordination branch" --no-verify
  git checkout "$current_branch"
  echo "  Created 'coordination' orphan branch with tasks/ directory"

  # Check for Spec-Kit
  if command -v specify &>/dev/null; then
    echo "  Spec-Kit found. Running 'specify init . --ai claude'..."
    specify init . --ai claude
  else
    echo ""
    echo "  Spec-Kit not found."
    read -rp "  Install Spec-Kit for planning phase? (y/N) " install_speckit
    if [[ "$install_speckit" =~ ^[Yy]$ ]]; then
      npm install -g @github/spec-kit
      if command -v specify &>/dev/null; then
        specify init . --ai claude
      fi
    else
      echo "  Skipping Spec-Kit. You can install later with: npm install -g @github/spec-kit"
    fi
  fi

  echo ""
  echo "Done! Next steps:"
  echo "  1. Edit .coordination/config.toml to customize task types"
  echo "  2. Edit .coordination/claude-md/*.md to customize agent prompts"
  echo "  3. Run 'coordinator plan' to generate tasks"
  echo "  4. Run 'coordinator start' to begin agent loops"
}

cmd_start() {
  echo "coordinator start — not yet implemented"
  exit 1
}

cmd_stop() {
  echo "coordinator stop — not yet implemented"
  exit 1
}

cmd_add_agent() {
  echo "coordinator add-agent — not yet implemented"
  exit 1
}

cmd_plan() {
  echo "coordinator plan — not yet implemented"
  exit 1
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  case "$1" in
  init)
    shift
    cmd_init "$@"
    ;;
  start)
    shift
    cmd_start "$@"
    ;;
  stop)
    shift
    cmd_stop "$@"
    ;;
  add-agent)
    shift
    cmd_add_agent "$@"
    ;;
  status)
    shift
    cmd_status "$@"
    ;;
  plan)
    shift
    cmd_plan "$@"
    ;;
  -h | --help) usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
  esac
}

main "$@"
