#!/usr/bin/env bash
set -euo pipefail

# Agent loop — one instance per agent, runs in agent's worktree
# Usage: agent-loop.sh <agent-name> <agent-command> <coord-worktree> <agent-worktree> <capabilities...>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Ensure node is available (wt.exe tabs start without .bashrc)
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

# Find main repo (parent of coordination worktree) for .coordination/claude-md files
MAIN_REPO="$(cd "$COORD_WORKTREE/.." && git rev-parse --show-toplevel)"
CLAUDE_MD_DIR="$MAIN_REPO/.coordination/claude-md"
CONFIG_JSON="$COORD_WORKTREE/config.json"

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

  # 4. Sync agent worktree with latest main
  cd "$AGENT_WORKTREE"
  git checkout -B "$AGENT_BRANCH" origin/main 2>/dev/null || git checkout -B "$AGENT_BRANCH" main
  git pull --rebase origin main 2>/dev/null || true

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
