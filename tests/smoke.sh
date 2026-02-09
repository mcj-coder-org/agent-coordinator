#!/usr/bin/env bash
set -euo pipefail

# Smoke test for coordinator CLI
# Opens real Windows Terminal tabs — requires manual observation.
#
# What to look for:
#   1. Two new WT tabs open ("smoke-agent-1" and "smoke-agent-2")
#   2. Each tab shows agent-loop.sh output: "Starting agent loop", "No tasks available"
#   3. coordinator status shows both agents' worktrees
#   4. coordinator stop closes cleanly
#   5. All temp worktrees removed
#
# Usage: npm run test:smoke

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORDINATOR="$SCRIPT_DIR/../bin/coordinator.sh"

SMOKE_DIR=""

cleanup() {
  echo ""
  echo "── Cleaning up ──"
  if [[ -n "$SMOKE_DIR" && -d "$SMOKE_DIR" ]]; then
    cd "$SMOKE_DIR"
    "$COORDINATOR" stop --clean 2>/dev/null || true
    cd /
    # Remove the worktrees that stop may have left
    for d in "$SMOKE_DIR"/../smoke-project-*; do
      [[ -d "$d" ]] && rm -rf "$d"
    done
    rm -rf "$SMOKE_DIR"
  fi
  echo "Done."
}
trap cleanup EXIT

prompt_continue() {
  local msg="${1:-Press Enter to continue...}"
  echo ""
  echo "  $msg"
  read -r
}

# ── Setup ──────────────────────────────────────────────

SMOKE_DIR=$(mktemp -d "/tmp/smoke-project.XXXXXX")
echo "=== Coordinator Smoke Test ==="
echo ""
echo "Temp directory: $SMOKE_DIR"

cd "$SMOKE_DIR"
git init -b main >/dev/null 2>&1
git commit --allow-empty -m "initial" --no-verify >/dev/null 2>&1

# Write agents config with two agents (both use 'echo' as a harmless command)
AGENTS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/coordinator/agents.toml"
AGENTS_CONFIG_BACKUP=""
if [[ -f "$AGENTS_CONFIG" ]]; then
  AGENTS_CONFIG_BACKUP="$AGENTS_CONFIG.smoke-backup"
  cp "$AGENTS_CONFIG" "$AGENTS_CONFIG_BACKUP"
  echo "Backed up existing agents.toml → $AGENTS_CONFIG_BACKUP"
fi

mkdir -p "$(dirname "$AGENTS_CONFIG")"
cat >"$AGENTS_CONFIG" <<'TOML'
[agents.smoke-agent-1]
command = "echo"
capabilities = ["implementation", "fixes"]

[agents.smoke-agent-2]
command = "echo"
capabilities = ["implementation"]
TOML

# Restore agents.toml on exit
restore_agents_config() {
  if [[ -n "$AGENTS_CONFIG_BACKUP" && -f "$AGENTS_CONFIG_BACKUP" ]]; then
    mv "$AGENTS_CONFIG_BACKUP" "$AGENTS_CONFIG"
    echo "Restored original agents.toml"
  else
    rm -f "$AGENTS_CONFIG"
  fi
}
trap 'restore_agents_config; cleanup' EXIT

# ── Test: init ─────────────────────────────────────────

echo ""
echo "── Step 1: coordinator init ──"
"$COORDINATOR" init </dev/null
echo ""
echo "CHECK: .coordination/ directory created with config and templates?"
ls -la .coordination/
ls -la .coordination/claude-md/
prompt_continue

# ── Test: start ────────────────────────────────────────

echo "── Step 2: coordinator start ──"
echo ""
echo "This will open Windows Terminal tabs."
echo "LOOK FOR: Two new tabs named 'smoke-agent-1' and 'smoke-agent-2'"
echo "EXPECT: Each tab shows 'Starting agent loop' then 'No tasks available. Sleeping...'"
prompt_continue "Press Enter to launch agents..."

"$COORDINATOR" start

echo ""
echo "CHECK: Did two new terminal tabs open?"
prompt_continue

# ── Test: status ───────────────────────────────────────

echo "── Step 3: coordinator status ──"
"$COORDINATOR" status
prompt_continue

# ── Test: stop ─────────────────────────────────────────

echo "── Step 4: coordinator stop ──"
echo ""
echo "LOOK FOR: Terminal tabs should close (or show the loop exiting)"
"$COORDINATOR" stop

echo ""
echo "CHECK: Worktrees removed?"
git worktree list
prompt_continue

# ── Summary ────────────────────────────────────────────

echo ""
echo "=== Smoke Test Complete ==="
echo ""
echo "Verify:"
echo "  [  ] Two terminal tabs opened (smoke-agent-1, smoke-agent-2)"
echo "  [  ] Agent loops started and logged to each tab"
echo "  [  ] coordinator status showed coordination state"
echo "  [  ] coordinator stop removed worktrees"
echo "  [  ] Terminal tabs closed or loops exited"
