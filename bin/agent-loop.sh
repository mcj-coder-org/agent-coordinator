#!/usr/bin/env bash
set -euo pipefail

# Agent loop — one instance per agent, runs in agent's worktree
# Usage: agent-loop.sh <agent-name> <agent-command> <coord-worktree> <agent-worktree> <capabilities...>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Enable alias expansion for non-interactive shell
shopt -s expand_aliases

# Source user profile to get aliases and PATH (wt.exe tabs start without .bashrc)
# shellcheck disable=SC1090,SC1091
[[ -f "$HOME/.bash_profile" ]] && . "$HOME/.bash_profile"
# shellcheck disable=SC1090,SC1091
[[ -f "$HOME/.bashrc" ]] && . "$HOME/.bashrc"
# shellcheck disable=SC1090,SC1091
[[ -f "$HOME/.profile" ]] && . "$HOME/.profile"

# Ensure node is available
if ! command -v node &>/dev/null; then
  # Try common node version managers
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  if ! command -v node &>/dev/null; then
    echo "ERROR: node not found in PATH." >&2
    echo "  Supported: nvm (~/.nvm), system node" >&2
    exit 1
  fi
fi

AGENT_NAME="${1:?Usage: agent-loop.sh <name> <command> <coord-worktree> <agent-worktree> <caps...>}"
AGENT_CMD="${2:?}"
COORD_WORKTREE="${3:?}"
AGENT_WORKTREE="${4:?}"
shift 4
AGENT_CAPS=("$@")

AGENT_BRANCH="agent/$AGENT_NAME"

# Find main repo from coordination worktree
# Worktrees have a .git file (not directory) that points to the main repo's .git/worktrees/<name>
# Extract the main repo path from that
MAIN_REPO_GIT_DIR="$(cd "$COORD_WORKTREE" && git rev-parse --git-common-dir)"
MAIN_REPO="$(cd "$MAIN_REPO_GIT_DIR/.." && pwd)"
CLAUDE_MD_DIR="$MAIN_REPO/.coordination/claude-md"
CONFIG_JSON="$COORD_WORKTREE/config.json"

# Detect the base branch (the branch from which coordinator was started)
BASE_BRANCH="$(cd "$MAIN_REPO" && git branch --show-current)"

IDLE_SLEEP=30
LOOP_SLEEP=5

log() {
  echo "[$(date '+%H:%M:%S')] [$AGENT_NAME] $*"
}

log "Starting agent loop"
log "  Command: $AGENT_CMD"
log "  Capabilities: ${AGENT_CAPS[*]}"
log "  Coord worktree: $COORD_WORKTREE"
log "  Agent worktree: $AGENT_WORKTREE"

# Reclaim any tasks that were left in claimed state by this agent
log "Reclaiming orphaned tasks..."
cd "$COORD_WORKTREE"
git pull --rebase origin coordination 2>/dev/null || true
node "$LIB_DIR/tasks.js" reclaim "$COORD_WORKTREE/tasks" "$AGENT_NAME" || true
if git diff --quiet tasks/; then
  log "No tasks to reclaim"
else
  git add tasks/
  git commit -m "reclaim: $AGENT_NAME orphaned tasks" --no-verify
  git push origin coordination 2>/dev/null || true
fi

# Clean agent worktree for fresh start
log "Cleaning agent worktree..."
cd "$AGENT_WORKTREE"
git reset --hard HEAD
git clean -fd

while true; do
  # 1. Sync coordination state
  log "Syncing coordination branch..."
  cd "$COORD_WORKTREE"
  git pull --rebase origin coordination 2>/dev/null || true

  # 2. Find highest-priority task matching capabilities
  log "Looking for tasks..."
  result=$(node "$LIB_DIR/tasks.js" claim \
    "$COORD_WORKTREE/tasks" \
    "$CONFIG_JSON" \
    "$AGENT_NAME" \
    "${AGENT_CAPS[@]}" 2>/dev/null) || true

  if [[ -z "$result" ]]; then
    log "No tasks available. Sleeping ${IDLE_SLEEP}s..."
    sleep "$IDLE_SLEEP"
    continue
  fi

  TASK_ID=$(echo "$result" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).taskId))")
  TASK_TYPE=$(echo "$result" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).taskType))")
  TASK_CLAUDE_MD=$(echo "$result" | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).claudeMd))")

  log "Claimed task $TASK_ID ($TASK_TYPE)"

  # 3. Push claim (competing consumer — push conflict = retry)
  cd "$COORD_WORKTREE"
  git add tasks/
  git commit -m "claim: $AGENT_NAME → $TASK_ID ($TASK_TYPE)" --no-verify
  if ! git push origin coordination 2>/dev/null; then
    log "Push conflict — someone else claimed it. Retrying..."
    git reset --hard HEAD~1
    git pull --rebase origin coordination 2>/dev/null || true
    continue
  fi

  # 4. Sync agent worktree with latest base branch
  cd "$AGENT_WORKTREE"
  git checkout -B "$AGENT_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null || git checkout -B "$AGENT_BRANCH" "$BASE_BRANCH"
  git pull --rebase origin "$BASE_BRANCH" 2>/dev/null || true

  # 5. Build prompt using task-type-specific CLAUDE.md
  TASK_FILE="$COORD_WORKTREE/tasks/$TASK_ID.json"
  CLAUDE_MD_FILE="$CLAUDE_MD_DIR/$TASK_CLAUDE_MD"
  prompt=$(node "$LIB_DIR/prompt-builder.js" "$TASK_FILE" "$CLAUDE_MD_FILE")

  # 6. Execute in FRESH context (one-shot, no carry-over)
  log "Executing $AGENT_CMD for task $TASK_ID..."
  cd "$AGENT_WORKTREE"
  if $AGENT_CMD -p "$prompt" --dangerously-skip-permissions; then
    log "Agent completed task $TASK_ID"
  else
    log "Agent failed on task $TASK_ID"
    cd "$COORD_WORKTREE"
    node "$LIB_DIR/tasks.js" update "$TASK_FILE" "failed" "$AGENT_NAME"
    git add tasks/ && git commit -m "failed: $TASK_ID" --no-verify
    git push origin coordination 2>/dev/null || true
    sleep "$LOOP_SLEEP"
    continue
  fi

  # 7. Commit + push code from agent worktree
  cd "$AGENT_WORKTREE"
  if git diff --quiet && git diff --cached --quiet; then
    log "No changes produced for task $TASK_ID"
  else
    git add -A
    git commit -m "task: $TASK_ID ($TASK_TYPE)" --no-verify
    git push origin "$AGENT_BRANCH" 2>/dev/null || git push --set-upstream origin "$AGENT_BRANCH"
  fi

  # 8. Update task status on coordination branch
  cd "$COORD_WORKTREE"
  node "$LIB_DIR/tasks.js" update "$TASK_FILE" "complete" "$AGENT_NAME"
  git add tasks/
  git commit -m "complete: $TASK_ID" --no-verify
  git push origin coordination 2>/dev/null || true

  log "Task $TASK_ID complete"
  sleep "$LOOP_SLEEP"
done
