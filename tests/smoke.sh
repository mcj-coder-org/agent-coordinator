#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test: full coordinator journey
#
# Demonstrates the complete lifecycle:
#   1. Initialize coordinator in a fresh project
#   2. Define tasks for a "Hello World" app (test → implement → review → fix)
#   3. Start agents with mock AI command
#   4. Watch agents claim tasks by capability and priority
#   5. Monitor progress until all tasks complete
#   6. Verify artifacts produced by agents
#   7. Shut down and clean up
#
# Opens real Windows Terminal tabs — requires manual observation.
# Uses a mock agent script instead of real AI.
#
# Usage: npm run test:smoke

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORDINATOR="$SCRIPT_DIR/../bin/coordinator.sh"

SMOKE_DIR=""
PROJECT_DIR=""
AGENTS_CONFIG_BACKUP=""
AGENTS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/coordinator/agents.toml"

# ── Helpers ────────────────────────────────────────────

bold() { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
dim() { printf '\033[2m%s\033[0m' "$*"; }

phase() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold "  Phase $1: $2"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

check() { echo "  $(green "✓") $1"; }
info() { echo "  $(dim "·") $1"; }
waiting() { echo "  $(yellow "⏳") $1"; }

prompt_continue() {
  local msg="${1:-Press Enter to continue...}"
  echo ""
  echo "  $msg"
  read -r
}

cleanup() {
  echo ""
  echo "── Cleaning up ──"

  # Restore agents.toml
  if [[ -n "$AGENTS_CONFIG_BACKUP" && -f "$AGENTS_CONFIG_BACKUP" ]]; then
    mv "$AGENTS_CONFIG_BACKUP" "$AGENTS_CONFIG"
    info "Restored original agents.toml"
  elif [[ -f "$AGENTS_CONFIG" ]]; then
    rm -f "$AGENTS_CONFIG"
  fi

  # Stop coordinator and remove worktrees
  if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    cd "$PROJECT_DIR"
    "$COORDINATOR" stop --clean 2>/dev/null || true
  fi

  # Remove temp directory and any leftover worktrees
  if [[ -n "$SMOKE_DIR" && -d "$SMOKE_DIR" ]]; then
    cd /
    for d in "$SMOKE_DIR"/hello-world-*; do
      [[ -d "$d" ]] && rm -rf "$d"
    done
    rm -rf "$SMOKE_DIR"
    info "Removed temp directory"
  fi

  echo "Done."
}
trap cleanup EXIT

# ── Phase 0: Setup ─────────────────────────────────────

echo ""
bold "=== Coordinator E2E Smoke Test ==="
echo ""
echo "This test demonstrates the full coordinator journey:"
echo "  Plan → Test → Implement → Review → Fix → Done"
echo ""
echo "It opens real Windows Terminal tabs with mock AI agents."
echo "Watch the tabs to see agents claim and complete tasks."

SMOKE_DIR=$(mktemp -d "/tmp/smoke-e2e.XXXXXX")
PROJECT_DIR="$SMOKE_DIR/hello-world"
info "Temp directory: $SMOKE_DIR"

# Create bare repo as "remote origin"
BARE_REPO="$SMOKE_DIR/origin.git"
git init --bare -b main "$BARE_REPO" >/dev/null 2>&1
info "Created bare repo (origin): $BARE_REPO"

# Clone as working project
git clone "$BARE_REPO" "$PROJECT_DIR" >/dev/null 2>&1
cd "$PROJECT_DIR"
git commit --allow-empty -m "initial commit" --no-verify >/dev/null 2>&1
git push origin main >/dev/null 2>&1
info "Created project: $PROJECT_DIR"

# Create mock agent script
MOCK_AGENT="$SMOKE_DIR/mock-agent.sh"
cat >"$MOCK_AGENT" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock AI agent — creates files based on task prompt keywords
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if echo "$prompt" | grep -qi "unit test"; then
  cat > hello.test.js << 'JS'
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { hello } = require("./hello.js");

test("hello returns default greeting", () => {
  assert.equal(hello(), "Hello, World!");
});

test("hello with name returns personalized greeting", () => {
  assert.equal(hello("Alice"), "Hello, Alice!");
});
JS
  echo "Created hello.test.js"

elif echo "$prompt" | grep -qi "Implement.*Hello World"; then
  cat > hello.js << 'JS'
function hello() {
  return "Hello, World!";
}

module.exports = { hello };
JS
  echo "Created hello.js"

elif echo "$prompt" | grep -qi "review"; then
  # Reviewer produces no code changes
  echo "Review complete: hello() should accept an optional name parameter"

elif echo "$prompt" | grep -qi "fix\|validation\|name parameter"; then
  cat > hello.js << 'JS'
function hello(name) {
  return name ? `Hello, ${name}!` : "Hello, World!";
}

module.exports = { hello };
JS
  echo "Updated hello.js with name parameter support"
fi
MOCKEOF
chmod +x "$MOCK_AGENT"
info "Created mock agent: $MOCK_AGENT"

# Backup and write agents.toml
if [[ -f "$AGENTS_CONFIG" ]]; then
  AGENTS_CONFIG_BACKUP="$AGENTS_CONFIG.smoke-backup"
  cp "$AGENTS_CONFIG" "$AGENTS_CONFIG_BACKUP"
  info "Backed up existing agents.toml"
fi
mkdir -p "$(dirname "$AGENTS_CONFIG")"
cat >"$AGENTS_CONFIG" <<TOML
[agents.implementer]
command = "$MOCK_AGENT"
capabilities = ["implementation", "fixes"]

[agents.reviewer]
command = "$MOCK_AGENT"
capabilities = ["review"]
TOML
info "Wrote agents.toml (implementer + reviewer)"

check "Setup complete"

# ── Phase 1: Initialize ───────────────────────────────

phase 1 "Initialize coordinator"

cd "$PROJECT_DIR"
"$COORDINATOR" init </dev/null 2>&1

# Commit .coordination/ to main and push
git add .coordination/ >/dev/null 2>&1
git commit -m "add coordination config" --no-verify >/dev/null 2>&1
git push origin main >/dev/null 2>&1
check "Committed .coordination/ to main"

# Push coordination branch to origin
git push origin coordination >/dev/null 2>&1
check "Pushed coordination branch to origin"

prompt_continue

# ── Phase 2: Define tasks ─────────────────────────────

phase 2 "Define tasks (simulating planner output)"

echo "  Creating 4 tasks for a Hello World app:"
echo ""
echo "    001 [implementation]  Write unit tests       (no blockers)"
echo "    002 [implementation]  Implement hello.js     (blocked by 001)"
echo "    003 [review]          Review implementation  (blocked by 002)"
echo "    004 [fixes]           Add name parameter     (blocked by 003)"
echo ""

git checkout coordination >/dev/null 2>&1

cat >tasks/001.json <<'JSON'
{
  "id": "001",
  "type": "implementation",
  "status": "pending",
  "description": "Write unit tests for Hello World module",
  "acceptanceCriteria": [
    "Test hello() returns 'Hello, World!'",
    "Test runs with node --test"
  ],
  "owns": ["hello.test.js"],
  "blockedBy": []
}
JSON

cat >tasks/002.json <<'JSON'
{
  "id": "002",
  "type": "implementation",
  "status": "pending",
  "description": "Implement Hello World module with hello() function",
  "acceptanceCriteria": [
    "hello() function returns 'Hello, World!'",
    "Exported as CommonJS module"
  ],
  "owns": ["hello.js"],
  "blockedBy": ["001"]
}
JSON

cat >tasks/003.json <<'JSON'
{
  "id": "003",
  "type": "review",
  "status": "pending",
  "description": "Review Hello World implementation for correctness and best practices",
  "acceptanceCriteria": [
    "Code follows project conventions",
    "Tests are adequate",
    "Suggest improvements if needed"
  ],
  "blockedBy": ["002"]
}
JSON

cat >tasks/004.json <<'JSON'
{
  "id": "004",
  "type": "fixes",
  "status": "pending",
  "description": "Fix: add input validation and name parameter to hello() function",
  "acceptanceCriteria": [
    "hello(name) accepts optional name parameter",
    "Returns 'Hello, World!' with no args",
    "Returns 'Hello, {name}!' with a name"
  ],
  "owns": ["hello.js"],
  "blockedBy": ["003"],
  "reviewFeedback": [
    {
      "reviewer": "reviewer",
      "verdict": "changes-requested",
      "comments": "hello() should accept an optional name parameter for personalized greetings"
    }
  ]
}
JSON

git add tasks/ >/dev/null 2>&1
git commit -m "add hello world tasks" --no-verify >/dev/null 2>&1
git push origin coordination >/dev/null 2>&1
git checkout main >/dev/null 2>&1

check "4 tasks created on coordination branch"

echo ""
echo "  Expected agent behavior:"
echo "    implementer claims 001 (only unblocked implementation task)"
echo "    reviewer idles (no review tasks yet)"
echo "    implementer completes 001, claims 002"
echo "    implementer completes 002, reviewer claims 003"
echo "    reviewer completes 003, implementer claims 004 (fixes=priority 100)"
echo "    implementer completes 004 — all done!"

prompt_continue "Press Enter to start agents..."

# ── Phase 3: Start agents ─────────────────────────────

phase 3 "Start agents"

echo "  This opens two Windows Terminal tabs:"
echo "    Tab 'implementer' — handles implementation + fixes tasks"
echo "    Tab 'reviewer'    — handles review tasks"
echo ""

"$COORDINATOR" start

check "Agents launched in terminal tabs"
echo ""
echo "  Watch the terminal tabs — you should see:"
echo "    implementer: 'Claimed task 001 (implementation)'"
echo "    reviewer:    'No tasks available. Sleeping...'"

prompt_continue

# ── Phase 4: Monitor progress ─────────────────────────

phase 4 "Monitor task progress"

PROJECT_NAME=$(basename "$PROJECT_DIR")
COORD_WT="$SMOKE_DIR/${PROJECT_NAME}-coordination"

echo "  Polling task status every 5 seconds..."
echo "  (Watch the WT tabs for real-time agent activity)"
echo ""

all_done=false
max_polls=30 # 150 seconds max
poll=0

while [[ "$all_done" != "true" && $poll -lt $max_polls ]]; do
  poll=$((poll + 1))

  # Pull latest coordination state
  cd "$COORD_WT"
  git pull --rebase origin coordination >/dev/null 2>&1 || true
  cd "$PROJECT_DIR"

  # Count task statuses
  total=0
  complete=0
  claimed=0
  pending=0
  status_line=""

  for task_file in "$COORD_WT"/tasks/*.json; do
    [[ -f "$task_file" ]] || continue
    [[ "$(basename "$task_file")" == ".gitkeep" ]] && continue
    total=$((total + 1))
    local_status=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).status)")
    local_id=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$task_file','utf8')).id)")
    case "$local_status" in
    complete)
      complete=$((complete + 1))
      status_line="$status_line $(green "[$local_id ✓]")"
      ;;
    claimed)
      claimed=$((claimed + 1))
      status_line="$status_line $(yellow "[$local_id ⚙]")"
      ;;
    *)
      pending=$((pending + 1))
      status_line="$status_line $(dim "[$local_id ·]")"
      ;;
    esac
  done

  printf "\r  Poll %2d: %s  (%d/%d complete)" "$poll" "$status_line" "$complete" "$total"

  if [[ $complete -eq $total && $total -gt 0 ]]; then
    all_done=true
    echo ""
    echo ""
    check "All $total tasks complete!"
  else
    sleep 5
  fi
done

if [[ "$all_done" != "true" ]]; then
  echo ""
  echo ""
  echo "  ⚠ Timed out after $((poll * 5)) seconds ($complete/$total complete)"
  echo "  Check the terminal tabs for errors."
  prompt_continue
fi

# ── Phase 5: Verify artifacts ─────────────────────────

phase 5 "Verify artifacts"

IMPL_WT="$SMOKE_DIR/${PROJECT_NAME}-implementer"

echo "  Checking files created by mock agents in implementer worktree:"
echo ""
if [[ -f "$IMPL_WT/hello.js" ]]; then
  check "hello.js exists"
  echo "    ┌─────────────────────────────────────"
  sed 's/^/    │ /' "$IMPL_WT/hello.js"
  echo "    └─────────────────────────────────────"
else
  echo "  ✗ hello.js not found"
fi
echo ""
if [[ -f "$IMPL_WT/hello.test.js" ]]; then
  check "hello.test.js exists"
  echo "    ┌─────────────────────────────────────"
  sed 's/^/    │ /' "$IMPL_WT/hello.test.js"
  echo "    └─────────────────────────────────────"
else
  echo "  ✗ hello.test.js not found"
fi

echo ""
echo "  Final task states:"
"$COORDINATOR" status 2>/dev/null || true

prompt_continue "Press Enter to shut down agents..."

# ── Phase 6: Shutdown ─────────────────────────────────

phase 6 "Shutdown"

"$COORDINATOR" stop --clean
check "Agents stopped, worktrees removed, branches cleaned"

echo ""
echo "  Remaining worktrees:"
git worktree list

# ── Summary ────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bold "  Smoke Test Complete"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Verify these observations:"
echo "    [  ] Two WT tabs opened (implementer + reviewer)"
echo "    [  ] implementer claimed 001, 002, 004 in sequence"
echo "    [  ] reviewer claimed 003 when unblocked"
echo "    [  ] fixes (004) was prioritized (priority 100 > implementation 50)"
echo "    [  ] hello.js has name parameter (fix applied)"
echo "    [  ] hello.test.js has both test cases"
echo "    [  ] coordinator stop cleaned up all worktrees"
echo ""
