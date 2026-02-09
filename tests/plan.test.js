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
