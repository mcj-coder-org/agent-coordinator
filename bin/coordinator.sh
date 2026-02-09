#!/usr/bin/env bash
set -euo pipefail

# Resolve symlinks to find actual script location (handles npm link)
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ -L "$SCRIPT_PATH" ]]; then
  SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

usage() {
  cat <<'EOF'
Usage: coordinator <command> [options]

Commands:
  init [--force]    Initialize .coordination/ in current project
                    --force: reinitialize (deletes existing setup)
  plan [tasks.md]   Convert Spec-Kit tasks.md to JSON task files
                    Auto-discovers specs/*/tasks.md if no path given
  start             Create worktrees and start agent loops
  stop              Stop agent loops and optionally clean worktrees
  add-agent         Spin up an additional agent
  status            Show current task and agent status

Options:
  -h, --help        Show this help message
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
  local coord_wt
  coord_wt=$(git worktree list | grep "coordination" | awk '{print $1}') || true
  if [[ -z "$coord_wt" ]]; then
    echo "Coordination worktree not found. Run 'coordinator start' first."
    return
  fi
  local tasks_dir="$coord_wt/tasks"

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
  local force=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --force)
      force=true
      shift
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      echo "Usage: coordinator init [--force]" >&2
      exit 1
      ;;
    esac
  done

  local coord_dir=".coordination"
  local templates_dir="$SCRIPT_DIR/../templates/coordination"

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  # Check if already initialized
  if [[ -d "$coord_dir" ]]; then
    if [[ "$force" == false ]]; then
      echo "Error: .coordination/ already exists (already initialized)." >&2
      echo "  Use 'coordinator init --force' to reinitialize." >&2
      exit 1
    fi
    echo "Reinitializing .coordination/ (--force)..."
    rm -rf "$coord_dir"

    # Delete coordination branch if it exists
    if git show-ref --verify --quiet refs/heads/coordination; then
      git branch -D coordination >/dev/null 2>&1
    fi
  else
    echo "Initializing .coordination/..."
  fi

  # Copy templates
  cp -r "$templates_dir" "$coord_dir"
  echo "  Created .coordination/ with config and CLAUDE.md templates"

  # Create coordination orphan branch
  local current_branch
  current_branch=$(git branch --show-current)
  git checkout --orphan coordination
  git rm -rf . >/dev/null 2>&1 || true
  mkdir -p tasks
  touch tasks/.gitkeep
  cat >README.md <<'HEREDOC'
# Coordination Branch

This branch holds task JSON files for agent coordination.
It is never merged to main.
HEREDOC
  git add tasks README.md
  git commit -m "init: coordination branch" --no-verify
  git checkout "$current_branch"
  echo "  Created 'coordination' orphan branch with tasks/ directory"

  # Check for Spec-Kit (optional planning tool)
  if command -v specify &>/dev/null; then
    echo "  Spec-Kit found. Running 'specify init . --ai claude'..."
    specify init . --ai claude --force
  else
    echo ""
    echo "  Spec-Kit not found (optional - for task planning)"
    echo "  To install Spec-Kit:"
    echo "    1. Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "    2. Install Spec-Kit: uv tool install specify-cli --from git+https://github.com/github/spec-kit.git"
    echo "  See: https://github.com/github/spec-kit"
  fi

  echo ""
  echo "Done! Next steps:"
  echo "  1. Edit .coordination/config.toml to customize task types"
  echo "  2. Edit .coordination/claude-md/*.md to customize agent prompts"
  echo "  3. Run 'coordinator plan' to generate tasks"
  echo "  4. Run 'coordinator start' to begin agent loops"
}

cmd_start() {
  local coord_dir=".coordination"
  if [[ ! -d "$coord_dir" ]]; then
    echo "Error: .coordination/ not found. Run 'coordinator init' first." >&2
    exit 1
  fi

  local agents_config="${XDG_CONFIG_HOME:-$HOME/.config}/coordinator/agents.toml"
  if [[ ! -f "$agents_config" ]]; then
    echo "Error: Agent config not found at $agents_config" >&2
    echo "Create it with your available agents. Example:" >&2
    echo '  [agents.claude-max]' >&2
    echo '  command = "claude"' >&2
    echo '  capabilities = ["implementation", "review"]' >&2
    exit 1
  fi

  local project_root
  project_root=$(git rev-parse --show-toplevel)
  local project_name
  project_name=$(basename "$project_root")

  # Create coordination worktree
  local coord_worktree="$project_root/../${project_name}-coordination"
  if [[ ! -d "$coord_worktree" ]]; then
    echo "Creating coordination worktree..."
    git worktree add "$coord_worktree" coordination
  fi

  # Convert TOML config to JSON for tasks.js
  local config_json="$coord_worktree/config.json"
  node -e "
    const { parseTOML } = require('$LIB_DIR/toml.js');
    const fs = require('fs');
    const toml = fs.readFileSync('$coord_dir/config.toml', 'utf8');
    fs.writeFileSync('$config_json', JSON.stringify(parseTOML(toml), null, 2));
  "

  # Parse agents from TOML config
  local agent_names=()
  local agent_commands=()
  local agent_capabilities=()
  local current_agent=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[agents\.([a-zA-Z0-9_-]+)\]$ ]]; then
      current_agent="${BASH_REMATCH[1]}"
      agent_names+=("$current_agent")
    elif [[ -n "$current_agent" && "$line" =~ ^command\ *=\ *\"(.+)\"$ ]]; then
      agent_commands+=("${BASH_REMATCH[1]}")
    elif [[ -n "$current_agent" && "$line" =~ ^capabilities\ *=\ *\[(.+)\]$ ]]; then
      local caps="${BASH_REMATCH[1]}"
      caps=$(echo "$caps" | sed 's/"//g; s/ //g')
      agent_capabilities+=("$caps")
    fi
  done <"$agents_config"

  echo "Found ${#agent_names[@]} agent(s) in config"

  # Create worktree + WT tab per agent
  for i in "${!agent_names[@]}"; do
    local name="${agent_names[$i]}"
    local cmd="${agent_commands[$i]}"
    local caps="${agent_capabilities[$i]}"
    local agent_worktree="$project_root/../${project_name}-${name}"

    # Create agent branch and worktree
    if [[ ! -d "$agent_worktree" ]]; then
      echo "Creating worktree for $name..."
      git branch "agent/$name" HEAD 2>/dev/null || true
      git worktree add "$agent_worktree" "agent/$name"
    fi

    # Launch in Windows Terminal tab
    echo "Launching $name in new terminal tab..."
    local loop_cmd="$SCRIPT_DIR/agent-loop.sh"
    # shellcheck disable=SC2086
    wt.exe -w 0 new-tab --title "$name" -- bash "$loop_cmd" \
      "$name" "$cmd" "$coord_worktree" "$agent_worktree" ${caps//,/ }
  done

  echo ""
  echo "All agents started. Use 'coordinator status' to monitor."
}

cmd_stop() {
  local clean=false
  if [[ "${1:-}" == "--clean" ]]; then
    clean=true
  fi

  local project_root
  project_root=$(git rev-parse --show-toplevel)
  local project_name
  project_name=$(basename "$project_root")

  echo "Stopping agents..."

  # Find and remove agent/coordination worktrees
  while IFS= read -r line; do
    local wt_path
    wt_path=$(echo "$line" | awk '{print $1}')
    local wt_name
    wt_name=$(basename "$wt_path")
    # Match worktrees created by coordinator (project-name-agentname or project-name-coordination)
    if [[ "$wt_name" == "${project_name}-"* && "$wt_path" != "$project_root" ]]; then
      echo "  Removing worktree: $wt_path"
      git worktree remove "$wt_path" --force 2>/dev/null || true
    fi
  done < <(git worktree list)

  if $clean; then
    echo "Cleaning up agent branches..."
    while IFS= read -r branch; do
      branch=$(echo "$branch" | tr -d ' *')
      if [[ "$branch" == agent/* ]]; then
        echo "  Deleting branch: $branch"
        git branch -D "$branch" 2>/dev/null || true
      fi
    done < <(git branch)
  fi

  echo "Done."
}

cmd_add_agent() {
  echo "coordinator add-agent — not yet implemented"
  exit 1
}

cmd_plan() {
  local coord_dir=".coordination"
  if [[ ! -d "$coord_dir" ]]; then
    echo "Error: .coordination/ not found. Run 'coordinator init' first." >&2
    exit 1
  fi

  local tasks_file="${1:-}"
  if [[ -z "$tasks_file" ]]; then
    # Auto-discover tasks.md in specs/ directory
    local specs_dirs=(specs/*/tasks.md)
    if [[ -e "${specs_dirs[0]}" ]]; then
      tasks_file="${specs_dirs[0]}"
      echo "Found tasks.md: $tasks_file"
    else
      echo "Error: No tasks.md file specified and none found in specs/*/" >&2
      echo "Usage: coordinator plan [path/to/tasks.md]" >&2
      exit 1
    fi
  fi

  if [[ ! -f "$tasks_file" ]]; then
    echo "Error: $tasks_file not found" >&2
    exit 1
  fi

  # Get current branch to return to
  local current_branch
  current_branch=$(git branch --show-current)

  # Switch to coordination branch
  git checkout coordination >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "Error: Could not checkout coordination branch" >&2
    exit 1
  fi

  # Run conversion
  echo "Converting $tasks_file to task JSON files..."
  node "$LIB_DIR/plan.js" "$tasks_file" tasks/

  if [[ $? -eq 0 ]]; then
    # Commit the tasks
    git add tasks/*.json
    git commit -m "plan: import tasks from $(basename "$tasks_file")" --no-verify
    echo "Tasks committed to coordination branch"
  else
    echo "Error: Failed to convert tasks" >&2
    git checkout "$current_branch" >/dev/null 2>&1
    exit 1
  fi

  # Return to original branch
  git checkout "$current_branch" >/dev/null 2>&1
  echo "Done. Tasks ready on coordination branch."
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
