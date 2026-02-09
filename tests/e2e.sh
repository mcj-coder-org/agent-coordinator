#!/usr/bin/env bash
set -euo pipefail

# E2E tests for coordinator CLI
# Runs in a disposable temp directory — safe to run repeatedly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORDINATOR="$SCRIPT_DIR/../bin/coordinator.sh"

PASS=0
FAIL=0
TEST_DIR=""
ORIGINAL_HOME="$HOME"

cleanup() {
  cd /
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    # Force-remove worktrees before deleting
    for repo in "$TEST_DIR"/*/; do
      if [[ -d "$repo/.git" || -f "$repo/.git" ]]; then
        (cd "$repo" && git worktree list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r wt; do
          git worktree remove --force "$wt" 2>/dev/null || true
        done) || true
      fi
    done
    rm -rf "$TEST_DIR"
  fi
  export HOME="$ORIGINAL_HOME"
}
trap cleanup EXIT

setup() {
  TEST_DIR=$(mktemp -d "/tmp/coordinator-e2e.XXXXXX")

  # Mock HOME so agents.toml doesn't collide with real config
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  # Git needs identity for commits
  git config --global user.email "test@test.com"
  git config --global user.name "Test"

  # Mock wt.exe so start doesn't actually open terminal tabs
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/wt.exe" <<'MOCK'
#!/usr/bin/env bash
echo "mock-wt: $*" >> "${MOCK_WT_LOG:-/dev/null}"
MOCK
  chmod +x "$TEST_DIR/bin/wt.exe"
  export PATH="$TEST_DIR/bin:$PATH"
}

# Create a fresh git repo with an initial commit
make_repo() {
  local name="${1:-project}"
  local repo="$TEST_DIR/$name"
  mkdir -p "$repo"
  cd "$repo"
  git init -b main >/dev/null 2>&1
  git commit --allow-empty -m "initial commit" --no-verify >/dev/null 2>&1
  echo "$repo"
}

# Write a minimal agents.toml
write_agents_config() {
  local config_dir="$HOME/.config/coordinator"
  mkdir -p "$config_dir"
  cat >"$config_dir/agents.toml" <<'TOML'
[agents.test-agent]
command = "echo"
capabilities = ["implementation", "fixes"]
TOML
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected NOT to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local desc="$1" expected_code="$2"
  shift 2
  local actual_code=0
  "$@" >/dev/null 2>&1 || actual_code=$?
  assert_eq "$desc" "$expected_code" "$actual_code"
}

assert_dir_exists() {
  local desc="$1" path="$2"
  if [[ -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — directory not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — file not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — directory should not exist: $path"
    FAIL=$((FAIL + 1))
  fi
}

# ── Tests ──────────────────────────────────────────────

test_help() {
  echo "── coordinator --help ──"
  local output
  output=$("$COORDINATOR" --help 2>&1)
  assert_contains "shows usage" "Usage: coordinator" "$output"
  assert_contains "lists init command" "init" "$output"
  assert_contains "lists start command" "start" "$output"
  assert_contains "lists stop command" "stop" "$output"
  assert_contains "lists status command" "status" "$output"
}

test_no_args() {
  echo "── coordinator (no args) ──"
  assert_exit "exits non-zero with no args" 1 "$COORDINATOR"
}

test_unknown_command() {
  echo "── coordinator bogus ──"
  local output
  output=$("$COORDINATOR" bogus 2>&1) || true
  assert_contains "shows unknown command error" "Unknown command: bogus" "$output"
}

test_init_not_git_repo() {
  echo "── init outside git repo ──"
  local dir="$TEST_DIR/not-a-repo"
  mkdir -p "$dir"
  cd "$dir"
  local output
  output=$("$COORDINATOR" init 2>&1) || true
  assert_contains "error mentions git" "not inside a git repository" "$output"
}

test_init_creates_coordination() {
  echo "── init creates .coordination/ ──"
  local repo
  repo=$(make_repo "init-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  assert_dir_exists ".coordination/ created" "$repo/.coordination"
  assert_file_exists "config.toml exists" "$repo/.coordination/config.toml"
  assert_dir_exists "claude-md/ exists" "$repo/.coordination/claude-md"
  assert_file_exists "implementer.md exists" "$repo/.coordination/claude-md/implementer.md"
}

test_init_creates_coordination_branch() {
  echo "── init creates coordination orphan branch ──"
  local repo
  repo=$(make_repo "init-branch-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1

  # Verify coordination branch exists
  local branches
  branches=$(git branch --list coordination)
  assert_contains "coordination branch exists" "coordination" "$branches"

  # Verify it has tasks/.gitkeep
  local files
  files=$(git ls-tree --name-only -r coordination)
  assert_contains "tasks/.gitkeep on coordination branch" "tasks/.gitkeep" "$files"
  assert_contains "README.md on coordination branch" "README.md" "$files"

  # Verify we're back on main
  local current
  current=$(git branch --show-current)
  assert_eq "back on main branch" "main" "$current"
}

test_init_already_exists() {
  echo "── init when .coordination/ already exists ──"
  local repo
  repo=$(make_repo "init-exists-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  local output
  output=$("$COORDINATOR" init 2>&1) || true
  assert_contains "error about existing" "already exists" "$output"
  assert_contains "mentions already initialized" "already initialized" "$output"
  assert_contains "mentions force flag" "--force" "$output"
}

test_init_force_reinitializes() {
  echo "── init --force reinitializes .coordination/ ──"
  local repo
  repo=$(make_repo "init-force-test")
  cd "$repo"

  # First init
  "$COORDINATOR" init </dev/null >/dev/null 2>&1

  # Modify config to verify it gets replaced
  echo "# modified" >>"$repo/.coordination/config.toml"
  local modified_content
  modified_content=$(cat "$repo/.coordination/config.toml")

  # Force reinit
  "$COORDINATOR" init --force </dev/null >/dev/null 2>&1

  # Verify .coordination exists
  assert_dir_exists ".coordination/ still exists" "$repo/.coordination"
  assert_file_exists "config.toml exists" "$repo/.coordination/config.toml"

  # Verify config was reset (no "# modified" comment)
  local new_content
  new_content=$(cat "$repo/.coordination/config.toml")
  assert_not_contains "config was reset" "# modified" "$new_content"
}

test_init_force_resets_coordination_branch() {
  echo "── init --force resets coordination branch ──"
  local repo
  repo=$(make_repo "init-force-branch-test")
  cd "$repo"

  # First init
  "$COORDINATOR" init </dev/null >/dev/null 2>&1

  # Add a file to coordination branch
  git checkout coordination >/dev/null 2>&1
  echo "test file" >tasks/test.txt
  git add tasks/test.txt
  git commit -m "add test file" --no-verify >/dev/null 2>&1
  git checkout main >/dev/null 2>&1

  # Force reinit
  "$COORDINATOR" init --force </dev/null >/dev/null 2>&1

  # Verify coordination branch exists
  local branches
  branches=$(git branch --list coordination)
  assert_contains "coordination branch exists" "coordination" "$branches"

  # Verify test.txt is gone (branch was reset)
  local files
  files=$(git ls-tree --name-only -r coordination)
  assert_not_contains "test file removed from branch" "test.txt" "$files"
  assert_contains "tasks/.gitkeep still exists" "tasks/.gitkeep" "$files"
}

test_status_no_coordination() {
  echo "── status without .coordination/ ──"
  local repo
  repo=$(make_repo "status-no-coord-test")
  cd "$repo"
  local output
  output=$("$COORDINATOR" status 2>&1) || true
  assert_contains "tells user to run init" "Run 'coordinator init' first" "$output"
}

test_status_no_worktree() {
  echo "── status with .coordination/ but no worktree ──"
  local repo
  repo=$(make_repo "status-no-wt-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  local output
  output=$("$COORDINATOR" status 2>&1)
  assert_contains "shows status header" "Agent Coordinator Status" "$output"
  assert_contains "tells user to run start" "Run 'coordinator start' first" "$output"
}

test_start_no_coordination() {
  echo "── start without .coordination/ ──"
  local repo
  repo=$(make_repo "start-no-coord-test")
  cd "$repo"
  local output
  output=$("$COORDINATOR" start 2>&1) || true
  assert_contains "tells user to run init" "Run 'coordinator init' first" "$output"
}

test_start_no_agents_config() {
  echo "── start without agents.toml ──"
  local repo
  repo=$(make_repo "start-no-agents-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  # Ensure no agents.toml exists
  rm -f "$HOME/.config/coordinator/agents.toml"
  local output
  output=$("$COORDINATOR" start 2>&1) || true
  assert_contains "error about agents config" "Agent config not found" "$output"
}

test_start_creates_worktrees() {
  echo "── start creates worktrees ──"
  local repo
  repo=$(make_repo "start-wt-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  write_agents_config
  export MOCK_WT_LOG="$TEST_DIR/wt.log"
  "$COORDINATOR" start >/dev/null 2>&1
  local project_name
  project_name=$(basename "$repo")

  # Coordination worktree
  assert_dir_exists "coordination worktree created" "$TEST_DIR/${project_name}-coordination"

  # Agent worktree
  assert_dir_exists "agent worktree created" "$TEST_DIR/${project_name}-test-agent"

  # wt.exe was called
  assert_file_exists "wt.exe was invoked" "$MOCK_WT_LOG"
  local wt_log
  wt_log=$(cat "$MOCK_WT_LOG")
  assert_contains "wt.exe called with agent name" "test-agent" "$wt_log"
}

test_status_with_worktree() {
  echo "── status with coordination worktree ──"
  # Reuse the repo from start test (worktrees still exist)
  local repo="$TEST_DIR/start-wt-test"
  cd "$repo"
  local output
  output=$("$COORDINATOR" status 2>&1)
  assert_contains "shows status header" "Agent Coordinator Status" "$output"
  assert_not_contains "no start-first message" "Run 'coordinator start' first" "$output"
}

test_status_with_tasks() {
  echo "── status shows task details ──"
  local repo="$TEST_DIR/start-wt-test"
  cd "$repo"
  local project_name
  project_name=$(basename "$repo")
  local coord_wt="$TEST_DIR/${project_name}-coordination"

  # Add a task to the coordination worktree
  cat >"$coord_wt/tasks/001.json" <<'JSON'
{
  "id": "001",
  "type": "implementation",
  "status": "claimed",
  "claimedBy": "test-agent"
}
JSON

  local output
  output=$("$COORDINATOR" status 2>&1)
  assert_contains "shows task id" "001" "$output"
  assert_contains "shows task status" "claimed" "$output"
  assert_contains "shows task type" "implementation" "$output"
  assert_contains "shows agent name" "test-agent" "$output"
}

test_stop_removes_worktrees() {
  echo "── stop removes worktrees ──"
  local repo="$TEST_DIR/start-wt-test"
  cd "$repo"
  local project_name
  project_name=$(basename "$repo")

  "$COORDINATOR" stop >/dev/null 2>&1

  assert_dir_not_exists "coordination worktree removed" "$TEST_DIR/${project_name}-coordination"
  assert_dir_not_exists "agent worktree removed" "$TEST_DIR/${project_name}-test-agent"

  # Agent branch should still exist (no --clean)
  local branches
  branches=$(git branch --list "agent/*")
  assert_contains "agent branch preserved" "agent/test-agent" "$branches"
}

test_stop_clean_removes_branches() {
  echo "── stop --clean removes agent branches ──"
  local repo
  repo=$(make_repo "stop-clean-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1
  write_agents_config
  export MOCK_WT_LOG="$TEST_DIR/wt-clean.log"
  "$COORDINATOR" start >/dev/null 2>&1
  "$COORDINATOR" stop --clean >/dev/null 2>&1

  local branches
  branches=$(git branch --list "agent/*")
  assert_eq "agent branches cleaned up" "" "$branches"
}

test_plan_converts_speckit_tasks() {
  echo "── plan converts tasks.md to JSON ──"
  local repo
  repo=$(make_repo "plan-test")
  cd "$repo"
  "$COORDINATOR" init </dev/null >/dev/null 2>&1

  # Create a sample tasks.md
  mkdir -p specs/001-test-feature
  cat >specs/001-test-feature/tasks.md <<'TASKS'
# Tasks: Test Feature

- [ ] T001 Create project structure
- [ ] T002 [P] Add model in src/model.py
- [ ] T003 [US1] Implement feature in src/feature.py
TASKS

  # Run plan command
  "$COORDINATOR" plan specs/001-test-feature/tasks.md >/dev/null 2>&1

  # Check coordination branch has tasks
  local project_name
  project_name=$(basename "$repo")
  local coord_wt="$TEST_DIR/${project_name}-coordination"

  # Create coordination worktree to check files
  git worktree add "$coord_wt" coordination >/dev/null 2>&1

  assert_file_exists "001.json created" "$coord_wt/tasks/001.json"
  assert_file_exists "002.json created" "$coord_wt/tasks/002.json"
  assert_file_exists "003.json created" "$coord_wt/tasks/003.json"

  # Verify JSON format
  local task001_status
  task001_status=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$coord_wt/tasks/001.json','utf8')).status)")
  assert_eq "task has pending status" "pending" "$task001_status"
}

# ── Runner ─────────────────────────────────────────────

main() {
  echo "=== Coordinator E2E Tests ==="
  echo ""

  setup

  test_help
  test_no_args
  test_unknown_command
  test_init_not_git_repo
  test_init_creates_coordination
  test_init_creates_coordination_branch
  test_init_already_exists
  test_init_force_reinitializes
  test_init_force_resets_coordination_branch
  test_status_no_coordination
  test_status_no_worktree
  test_start_no_coordination
  test_start_no_agents_config
  test_start_creates_worktrees
  test_status_with_worktree
  test_status_with_tasks
  test_stop_removes_worktrees
  test_stop_clean_removes_branches
  test_plan_converts_speckit_tasks

  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="

  if [[ $FAIL -gt 0 ]]; then
    exit 1
  fi
}

main
