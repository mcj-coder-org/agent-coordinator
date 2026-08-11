# Coordinator Plan Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement `coordinator plan` command that converts Spec-Kit's tasks.md markdown format to coordinator's JSON task format on the coordination branch.

**Architecture:** Parser reads Spec-Kit tasks.md markdown checklists, extracts task metadata (ID, description, files, user story labels, parallelization markers), converts to coordinator JSON schema with execution fields (status, claimedBy, history, owns, touches, blockedBy), and writes to coordination branch tasks/ directory.

**Tech Stack:** Node.js (built-in modules only), Bash (coordinator.sh), Git (coordination branch operations)

---

## Task 1: Create Spec-Kit Parser Module

**Files:**

- Create: `lib/speckit-parser.js`
- Test: `tests/speckit-parser.test.js`

**Step 1: Write the failing test**

Create test file:

```javascript
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseTasksMarkdown } = require('../lib/speckit-parser.js');

describe('parseTasksMarkdown', () => {
  it('parses basic task without markers', () => {
    const markdown = '- [ ] T001 Create project structure per implementation plan';

    const result = parseTasksMarkdown(markdown);

    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T001');
    assert.equal(result[0].description, 'Create project structure per implementation plan');
    assert.equal(result[0].parallel, false);
    assert.equal(result[0].userStory, null);
  });

  it('parses task with parallel marker', () => {
    const markdown = '- [ ] T002 [P] Implement auth middleware in src/middleware/auth.py';

    const result = parseTasksMarkdown(markdown);

    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T002');
    assert.equal(result[0].parallel, true);
    assert.deepEqual(result[0].files, ['src/middleware/auth.py']);
  });

  it('parses task with user story label', () => {
    const markdown = '- [ ] T012 [P] [US1] Create User model in src/models/user.py';

    const result = parseTasksMarkdown(markdown);

    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T012');
    assert.equal(result[0].parallel, true);
    assert.equal(result[0].userStory, 'US1');
    assert.deepEqual(result[0].files, ['src/models/user.py']);
  });

  it('ignores completed tasks', () => {
    const markdown = '- [x] T001 Already done\n- [ ] T002 Still pending';

    const result = parseTasksMarkdown(markdown);

    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T002');
  });

  it('parses multiple tasks', () => {
    const markdown = `
- [ ] T001 Setup project
- [ ] T002 [P] Add model in src/model.py
- [ ] T003 [US1] Implement feature in src/feature.py
`;

    const result = parseTasksMarkdown(markdown);

    assert.equal(result.length, 3);
  });

  it('extracts file paths from description', () => {
    const markdown = '- [ ] T001 Create User in src/models/user.py and tests/test_user.py';

    const result = parseTasksMarkdown(markdown);

    assert.deepEqual(result[0].files, ['src/models/user.py', 'tests/test_user.py']);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test tests/speckit-parser.test.js`

Expected: FAIL with "Cannot find module '../lib/speckit-parser.js'"

**Step 3: Write minimal implementation**

Create the parser module:

```javascript
/**
 * Parse Spec-Kit tasks.md markdown into structured task objects
 */

function parseTasksMarkdown(markdown) {
  const lines = markdown.split('\n');
  const tasks = [];

  // Regex: - [ ] T001 [P]? [US#]? Description with/without files
  const taskRegex = /^- \[ \] (T\d+)\s*(\[P\])?\s*(\[US\d+\])?\s*(.+)$/;

  for (const line of lines) {
    const match = line.match(taskRegex);
    if (!match) continue;

    const [, taskId, parallelMarker, userStoryMarker, description] = match;

    // Extract file paths (match path patterns like src/file.py, tests/file.js)
    const fileRegex = /\b[\w\-./]+\/[\w\-./]+\.\w+\b/g;
    const files = description.match(fileRegex) || [];

    tasks.push({
      taskId,
      description: description.trim(),
      parallel: Boolean(parallelMarker),
      userStory: userStoryMarker ? userStoryMarker.replace(/[\[\]]/g, '') : null,
      files,
    });
  }

  return tasks;
}

module.exports = { parseTasksMarkdown };
```

**Step 4: Run test to verify it passes**

Run: `npm test tests/speckit-parser.test.js`

Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add lib/speckit-parser.js tests/speckit-parser.test.js
git commit -m "feat: add Spec-Kit tasks.md parser"
```

---

## Task 2: Create Task Converter Module

**Files:**

- Create: `lib/task-converter.js`
- Test: `tests/task-converter.test.js`

**Step 1: Write the failing test**

Create test file:

```javascript
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { convertToCoordinatorTask } = require('../lib/task-converter.js');

describe('convertToCoordinatorTask', () => {
  it('converts basic spec-kit task to coordinator format', () => {
    const specKitTask = {
      taskId: 'T001',
      description: 'Create project structure per implementation plan',
      parallel: false,
      userStory: null,
      files: [],
    };

    const result = convertToCoordinatorTask(specKitTask, 1);

    assert.equal(result.id, '001');
    assert.equal(result.type, 'implementation');
    assert.equal(result.status, 'pending');
    assert.equal(result.description, 'Create project structure per implementation plan');
    assert.deepEqual(result.blockedBy, []);
    assert.equal(result.claimedBy, null);
    assert.deepEqual(result.history, []);
  });

  it('assigns files to owns when task is parallel', () => {
    const specKitTask = {
      taskId: 'T002',
      description: 'Create User model in src/models/user.py',
      parallel: true,
      userStory: 'US1',
      files: ['src/models/user.py'],
    };

    const result = convertToCoordinatorTask(specKitTask, 2);

    assert.deepEqual(result.owns, ['src/models/user.py']);
    assert.deepEqual(result.touches, []);
  });

  it('assigns files to touches when task is not parallel', () => {
    const specKitTask = {
      taskId: 'T003',
      description: 'Integrate components in src/main.py',
      parallel: false,
      userStory: 'US1',
      files: ['src/main.py'],
    };

    const result = convertToCoordinatorTask(specKitTask, 3);

    assert.deepEqual(result.owns, []);
    assert.deepEqual(result.touches, ['src/main.py']);
  });

  it('handles multiple files', () => {
    const specKitTask = {
      taskId: 'T004',
      description: 'Create model and test in src/model.py and tests/test.py',
      parallel: true,
      userStory: null,
      files: ['src/model.py', 'tests/test.py'],
    };

    const result = convertToCoordinatorTask(specKitTask, 4);

    assert.deepEqual(result.owns, ['src/model.py', 'tests/test.py']);
  });

  it('converts task ID to zero-padded numeric ID', () => {
    const specKitTask = {
      taskId: 'T042',
      description: 'Some task',
      parallel: false,
      userStory: null,
      files: [],
    };

    const result = convertToCoordinatorTask(specKitTask, 42);

    assert.equal(result.id, '042');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test tests/task-converter.test.js`

Expected: FAIL with "Cannot find module '../lib/task-converter.js'"

**Step 3: Write minimal implementation**

Create the converter module:

```javascript
/**
 * Convert Spec-Kit task format to coordinator JSON format
 */

function convertToCoordinatorTask(specKitTask, sequenceNumber) {
  // Convert to zero-padded ID (1 -> "001", 42 -> "042")
  const id = String(sequenceNumber).padStart(3, '0');

  // Determine type from user story or default to implementation
  const type = 'implementation';

  // Parallel tasks own files (exclusive), non-parallel tasks touch files (shared)
  const owns = specKitTask.parallel ? specKitTask.files : [];
  const touches = specKitTask.parallel ? [] : specKitTask.files;

  return {
    id,
    type,
    status: 'pending',
    description: specKitTask.description,
    owns,
    touches,
    blockedBy: [],
    claimedBy: null,
    history: [],
  };
}

module.exports = { convertToCoordinatorTask };
```

**Step 4: Run test to verify it passes**

Run: `npm test tests/task-converter.test.js`

Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add lib/task-converter.js tests/task-converter.test.js
git commit -m "feat: add task converter from Spec-Kit to coordinator format"
```

---

## Task 3: Add Dependency Resolution Logic

**Files:**

- Modify: `lib/task-converter.js`
- Modify: `tests/task-converter.test.js`

**Step 1: Write the failing test**

Add to `tests/task-converter.test.js`:

```javascript
const { buildDependencyGraph } = require('../lib/task-converter.js');

describe('buildDependencyGraph', () => {
  it('builds blockedBy for tasks that share files', () => {
    const tasks = [
      {
        taskId: 'T001',
        description: 'Create model in src/model.py',
        parallel: true,
        files: ['src/model.py'],
      },
      {
        taskId: 'T002',
        description: 'Update model in src/model.py',
        parallel: false,
        files: ['src/model.py'],
      },
    ];

    const result = buildDependencyGraph(tasks);

    // T002 depends on T001 because they share src/model.py
    assert.deepEqual(result[1].blockedBy, ['001']);
  });

  it('no dependencies for tasks with different files', () => {
    const tasks = [
      {
        taskId: 'T001',
        description: 'Create user in src/user.py',
        parallel: true,
        files: ['src/user.py'],
      },
      {
        taskId: 'T002',
        description: 'Create post in src/post.py',
        parallel: true,
        files: ['src/post.py'],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, []);
  });

  it('multiple dependencies for task touching multiple files', () => {
    const tasks = [
      {
        taskId: 'T001',
        description: 'Create user in src/user.py',
        parallel: true,
        files: ['src/user.py'],
      },
      {
        taskId: 'T002',
        description: 'Create post in src/post.py',
        parallel: true,
        files: ['src/post.py'],
      },
      {
        taskId: 'T003',
        description: 'Integrate in src/user.py and src/post.py',
        parallel: false,
        files: ['src/user.py', 'src/post.py'],
      },
    ];

    const result = buildDependencyGraph(tasks);

    // T003 depends on both T001 and T002
    assert.deepEqual(result[2].blockedBy, ['001', '002']);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test tests/task-converter.test.js`

Expected: FAIL with "buildDependencyGraph is not a function"

**Step 3: Write minimal implementation**

Add to `lib/task-converter.js`:

```javascript
/**
 * Build dependency graph based on file ownership
 * Tasks that touch files "owned" by earlier tasks must wait
 */
function buildDependencyGraph(specKitTasks) {
  const coordinatorTasks = specKitTasks.map((task, index) =>
    convertToCoordinatorTask(task, index + 1),
  );

  // Build file ownership map: file -> earliest task that owns/touches it
  const fileOwners = new Map();

  for (let i = 0; i < coordinatorTasks.length; i++) {
    const task = coordinatorTasks[i];
    const allFiles = [...task.owns, ...task.touches];

    for (const file of allFiles) {
      if (!fileOwners.has(file)) {
        fileOwners.set(file, []);
      }
      fileOwners.get(file).push(task.id);
    }
  }

  // Set blockedBy for tasks that touch files owned by earlier tasks
  for (let i = 0; i < coordinatorTasks.length; i++) {
    const task = coordinatorTasks[i];
    const allFiles = [...task.owns, ...task.touches];
    const dependencies = new Set();

    for (const file of allFiles) {
      const owners = fileOwners.get(file) || [];
      for (const ownerId of owners) {
        // Add as dependency if it's an earlier task
        if (ownerId < task.id) {
          dependencies.add(ownerId);
        }
      }
    }

    task.blockedBy = Array.from(dependencies).sort();
  }

  return coordinatorTasks;
}

module.exports = { convertToCoordinatorTask, buildDependencyGraph };
```

**Step 4: Run test to verify it passes**

Run: `npm test tests/task-converter.test.js`

Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add lib/task-converter.js tests/task-converter.test.js
git commit -m "feat: add dependency graph builder for task ordering"
```

---

## Task 4: Create CLI Interface for Plan Command

**Files:**

- Create: `lib/plan.js`
- Test: `tests/plan.test.js`

**Step 1: Write the failing test**

Create test file:

```javascript
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');

describe('plan CLI', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-plan-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('converts tasks.md to JSON files', () => {
    const tasksMarkdown = `# Tasks: Test Feature

## Phase 1: Setup

- [ ] T001 Create project structure
- [ ] T002 [P] Setup config in config/app.yaml

## Phase 2: Implementation

- [ ] T003 [P] [US1] Create User model in src/models/user.py
- [ ] T004 [US1] Add UserService in src/services/user.py
`;

    const tasksFile = path.join(tmpDir, 'tasks.md');
    fs.writeFileSync(tasksFile, tasksMarkdown);

    const outputDir = path.join(tmpDir, 'tasks');
    fs.mkdirSync(outputDir);

    execFileSync('node', [path.join(__dirname, '..', 'lib', 'plan.js'), tasksFile, outputDir], {
      encoding: 'utf8',
    });

    // Check files were created
    const files = fs.readdirSync(outputDir);
    assert.equal(files.length, 4);
    assert.ok(files.includes('001.json'));
    assert.ok(files.includes('002.json'));
    assert.ok(files.includes('003.json'));
    assert.ok(files.includes('004.json'));

    // Check content of one file
    const task001 = JSON.parse(fs.readFileSync(path.join(outputDir, '001.json'), 'utf8'));
    assert.equal(task001.id, '001');
    assert.equal(task001.status, 'pending');
    assert.equal(task001.description, 'Create project structure');
  });

  it('sets dependencies for tasks with shared files', () => {
    const tasksMarkdown = `
- [ ] T001 [P] Create model in src/model.py
- [ ] T002 Update model in src/model.py
`;

    const tasksFile = path.join(tmpDir, 'tasks.md');
    fs.writeFileSync(tasksFile, tasksMarkdown);

    const outputDir = path.join(tmpDir, 'tasks');
    fs.mkdirSync(outputDir);

    execFileSync('node', [path.join(__dirname, '..', 'lib', 'plan.js'), tasksFile, outputDir], {
      encoding: 'utf8',
    });

    const task002 = JSON.parse(fs.readFileSync(path.join(outputDir, '002.json'), 'utf8'));
    assert.deepEqual(task002.blockedBy, ['001']);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test tests/plan.test.js`

Expected: FAIL with "Cannot find module '../lib/plan.js'"

**Step 3: Write minimal implementation**

Create CLI module:

```javascript
#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { parseTasksMarkdown } = require('./speckit-parser.js');
const { buildDependencyGraph } = require('./task-converter.js');

function main() {
  const [, , tasksFile, outputDir] = process.argv;

  if (!tasksFile || !outputDir) {
    console.error('Usage: node plan.js <tasks.md> <output-dir>');
    process.exit(1);
  }

  if (!fs.existsSync(tasksFile)) {
    console.error(`Error: ${tasksFile} not found`);
    process.exit(1);
  }

  if (!fs.existsSync(outputDir)) {
    console.error(`Error: ${outputDir} not found`);
    process.exit(1);
  }

  // Read and parse tasks.md
  const markdown = fs.readFileSync(tasksFile, 'utf8');
  const specKitTasks = parseTasksMarkdown(markdown);

  if (specKitTasks.length === 0) {
    console.error('Error: No tasks found in tasks.md');
    process.exit(1);
  }

  // Convert to coordinator format with dependencies
  const coordinatorTasks = buildDependencyGraph(specKitTasks);

  // Write JSON files
  for (const task of coordinatorTasks) {
    const filename = path.join(outputDir, `${task.id}.json`);
    fs.writeFileSync(filename, JSON.stringify(task, null, 2) + '\n');
  }

  console.log(`Converted ${coordinatorTasks.length} tasks to ${outputDir}/`);
}

if (require.main === module) {
  main();
}

module.exports = { main };
```

**Step 4: Run test to verify it passes**

Run: `npm test tests/plan.test.js`

Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add lib/plan.js tests/plan.test.js
git commit -m "feat: add plan CLI for converting tasks.md to JSON"
```

---

## Task 5: Integrate with coordinator.sh

**Files:**

- Modify: `bin/coordinator.sh`

**Step 1: Write the failing test**

Add to `tests/e2e.sh`:

```bash
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
```

**Step 2: Run test to verify it fails**

Run: `npm run test:e2e`

Expected: FAIL with "coordinator plan — not yet implemented"

**Step 3: Implement cmd_plan in coordinator.sh**

Replace the `cmd_plan` function in `bin/coordinator.sh`:

```bash
cmd_plan() {
  local coord_dir=".coordination"
  if [[ ! -d "$coord_dir" ]]; then
    echo "Error: .coordination/ not found. Run 'coordinator init' first." >&2
    exit 1
  fi

  local tasks_file="$1"
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
```

**Step 4: Run test to verify it passes**

Run: `npm run test:e2e`

Expected: PASS (new test passes)

**Step 5: Update test runner**

Add the new test to the runner in `tests/e2e.sh`:

```bash
main() {
  # ... existing tests ...
  test_plan_converts_speckit_tasks
  # ... rest of tests ...
}
```

**Step 6: Run full test suite**

Run: `npm run test:e2e`

Expected: All tests pass including new plan test

**Step 7: Commit**

```bash
git add bin/coordinator.sh tests/e2e.sh
git commit -m "feat: implement coordinator plan command"
```

---

## Task 6: Update Documentation

**Files:**

- Modify: `README.md`
- Modify: `bin/coordinator.sh` (usage text)

**Step 1: Update usage text**

Modify the `usage()` function in `bin/coordinator.sh`:

```bash
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
```

**Step 2: Update README.md**

Add usage section after Requirements:

````markdown
## Usage

### 1. Initialize Coordinator

```bash
coordinator init
```
````

Creates `.coordination/` directory and `coordination` branch for task tracking.

### 2. Generate Tasks (with Spec-Kit)

If you have Spec-Kit installed and have created a `tasks.md`:

```bash
# Auto-discover tasks.md in specs/ directory
coordinator plan

# Or specify path explicitly
coordinator plan specs/001-my-feature/tasks.md
```

This converts Spec-Kit's markdown tasks to JSON files on the coordination branch.

### 3. Manually Create Tasks (without Spec-Kit)

Create JSON files directly on the coordination branch:

```bash
git checkout coordination
cat > tasks/001.json <<JSON
{
  "id": "001",
  "type": "implementation",
  "status": "pending",
  "description": "Implement user authentication",
  "acceptanceCriteria": ["User can log in", "Session persists"],
  "owns": ["src/auth/login.js"],
  "touches": [],
  "blockedBy": [],
  "claimedBy": null,
  "history": []
}
JSON
git add tasks/001.json
git commit -m "Add task 001"
git checkout main
```

See `.coordination/claude-md/planner.md` for the full task JSON schema.

### 4. Start Agents

```bash
coordinator start
```

Creates worktrees and launches agents in Windows Terminal tabs.

### 5. Monitor Progress

```bash
coordinator status
```

Shows which tasks are pending, claimed, or complete.

````

**Step 3: Commit**

```bash
git add bin/coordinator.sh README.md
git commit -m "docs: add coordinator plan usage documentation"
````

---

## Task 7: Manual Integration Test

**Files:**

- N/A (manual testing)

**Step 1: Test with real Spec-Kit output**

```bash
# Use the speckit-test directory we created earlier
cd /tmp/speckit-test

# Copy to agent-coordinator project
cd /home/mcjarvis/projects/agent-coordinator
coordinator init --force

# Create a simple tasks.md for testing
mkdir -p specs/001-test-feature
cat > specs/001-test-feature/tasks.md <<'TASKS'
# Tasks: Test Feature

## Phase 1: Setup

- [ ] T001 Create project structure per implementation plan
- [ ] T002 [P] Initialize config in config/settings.yaml

## Phase 2: Implementation

- [ ] T003 [P] [US1] Create User model in src/models/user.py
- [ ] T004 [US1] Implement UserService in src/services/user_service.py
- [ ] T005 [P] [US1] Add user endpoints in src/api/users.py

## Phase 3: Testing

- [ ] T006 [US1] Write tests in tests/test_users.py
TASKS

# Run the plan command
coordinator plan
```

**Step 2: Verify output**

Check that tasks were created correctly:

```bash
# Create coordination worktree to inspect
git worktree add ../agent-coordinator-coordination coordination

# List tasks
ls ../agent-coordinator-coordination/tasks/

# Check a task file
cat ../agent-coordinator-coordination/tasks/001.json

# Verify dependencies
# T004 should depend on T003 (both touch user-related files)
cat ../agent-coordinator-coordination/tasks/004.json | grep blockedBy
```

**Step 3: Test coordinator start**

Ensure tasks are properly loaded by agents:

```bash
coordinator status
# Should show the imported tasks
```

**Step 4: Clean up**

```bash
git worktree remove ../agent-coordinator-coordination
coordinator stop --clean
```

**Step 5: Document findings**

If any issues found, fix them and re-test. No commit needed for manual testing.

---

## Task 8: Final Testing and Cleanup

**Files:**

- N/A

**Step 1: Run all tests**

```bash
npm test
npm run test:e2e
npm run lint:sh
```

Expected: All tests pass, no lint errors

**Step 2: Test in clean environment**

```bash
# Create fresh test repo
cd /tmp
mkdir coordinator-final-test
cd coordinator-final-test
git init -b main
git config user.email "test@test.com"
git config user.name "Test"
git commit --allow-empty -m "initial" --no-verify

# Initialize and test plan
coordinator init
mkdir -p specs/001-demo
cat > specs/001-demo/tasks.md <<'TASKS'
- [ ] T001 Setup project
- [ ] T002 [P] Add feature in src/feature.js
TASKS

coordinator plan
coordinator status
```

**Step 3: Verify coordinator status shows tasks**

Expected: Status shows 2 pending tasks

**Step 4: Clean up test repo**

```bash
cd /home/mcjarvis/projects/agent-coordinator
```

---

## Verification Checklist

- [ ] All unit tests pass (`npm test`)
- [ ] All E2E tests pass (`npm run test:e2e`)
- [ ] Shellcheck passes (`npm run lint:sh`)
- [ ] `coordinator plan` converts tasks.md to JSON
- [ ] Dependencies are correctly set based on file ownership
- [ ] Parallel markers are converted to `owns` field
- [ ] User story labels are preserved
- [ ] Auto-discovery finds tasks.md in specs/
- [ ] Manual path specification works
- [ ] Tasks are committed to coordination branch
- [ ] `coordinator status` shows imported tasks
- [ ] Documentation is updated
- [ ] Usage help text includes plan command

---

## Notes

- **Zero external dependencies**: Uses only Node.js built-ins
- **TDD approach**: Tests written first for each module
- **Incremental commits**: Commit after each task
- **File-based dependencies**: Tasks that touch the same files are ordered
- **Spec-Kit compatibility**: Handles all Spec-Kit task formats ([P], [US#], etc.)
