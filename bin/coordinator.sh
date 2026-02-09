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
  echo "coordinator init — not yet implemented"
  exit 1
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
