const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const { listTasks } = require('../lib/tasks.js');

describe('listTasks', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('reads all task JSON files from a directory', () => {
    fs.writeFileSync(
      path.join(tmpDir, '001.json'),
      JSON.stringify({ id: '001', type: 'implement', status: 'pending' }),
    );
    fs.writeFileSync(
      path.join(tmpDir, '002.json'),
      JSON.stringify({ id: '002', type: 'review', status: 'pending' }),
    );

    const tasks = listTasks(tmpDir);
    assert.equal(tasks.length, 2);
    assert.equal(tasks[0].id, '001');
    assert.equal(tasks[1].id, '002');
  });

  it('returns empty array for empty directory', () => {
    const tasks = listTasks(tmpDir);
    assert.equal(tasks.length, 0);
  });

  it('ignores non-JSON files', () => {
    fs.writeFileSync(path.join(tmpDir, '001.json'), JSON.stringify({ id: '001' }));
    fs.writeFileSync(path.join(tmpDir, 'README.md'), '# tasks');

    const tasks = listTasks(tmpDir);
    assert.equal(tasks.length, 1);
  });
});

const { findClaimable } = require('../lib/tasks.js');

describe('findClaimable', () => {
  const tasks = [
    { id: '001', type: 'implement', status: 'pending', blockedBy: [] },
    { id: '002', type: 'review', status: 'pending', blockedBy: [] },
    { id: '003', type: 'implement', status: 'claimed', blockedBy: [] },
    { id: '004', type: 'fixes', status: 'pending', blockedBy: ['001'] },
  ];

  const taskTypes = {
    implement: { priority: 50 },
    review: { priority: 90 },
    fixes: { priority: 100 },
  };

  it('returns only pending tasks matching capabilities', () => {
    const result = findClaimable(tasks, ['implement'], taskTypes, tasks);
    assert.equal(result.length, 1);
    assert.equal(result[0].id, '001');
  });

  it('sorts by task-type priority descending', () => {
    const result = findClaimable(tasks, ['implement', 'review'], taskTypes, tasks);
    assert.equal(result[0].id, '002'); // review=90 > implement=50
    assert.equal(result[1].id, '001');
  });

  it('excludes tasks with unresolved blockers', () => {
    const result = findClaimable(tasks, ['fixes', 'implement'], taskTypes, tasks);
    // 004 (fixes) is blocked by 001 which is pending, so excluded
    assert.equal(result.length, 1);
    assert.equal(result[0].id, '001');
  });

  it('includes tasks whose blockers are all done', () => {
    const doneTasks = tasks.map((t) => (t.id === '001' ? { ...t, status: 'done' } : t));
    const result = findClaimable(doneTasks, ['fixes'], taskTypes, doneTasks);
    assert.equal(result.length, 1);
    assert.equal(result[0].id, '004');
  });

  it('treats complete status as done for blocker resolution', () => {
    const completeTasks = tasks.map((t) => (t.id === '001' ? { ...t, status: 'complete' } : t));
    const result = findClaimable(completeTasks, ['fixes'], taskTypes, completeTasks);
    assert.equal(result.length, 1);
    assert.equal(result[0].id, '004');
  });

  it('returns empty when no tasks match', () => {
    const result = findClaimable(tasks, ['planning'], taskTypes, tasks);
    assert.equal(result.length, 0);
  });
});

const { claimTask, updateTask } = require('../lib/tasks.js');

describe('claimTask', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('sets status to claimed and records agent', () => {
    const taskFile = path.join(tmpDir, '001.json');
    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        type: 'implement',
        status: 'pending',
        claimedBy: null,
        history: [],
      }),
    );

    const result = claimTask(taskFile, 'agent-1');
    assert.equal(result.status, 'claimed');
    assert.equal(result.claimedBy, 'agent-1');
    assert.equal(result.history.length, 1);
    assert.equal(result.history[0].status, 'claimed');
    assert.equal(result.history[0].agent, 'agent-1');

    // Verify written to disk
    const onDisk = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
    assert.equal(onDisk.status, 'claimed');
    assert.equal(onDisk.claimedBy, 'agent-1');
  });

  it('throws if task is not pending', () => {
    const taskFile = path.join(tmpDir, '001.json');
    fs.writeFileSync(taskFile, JSON.stringify({ id: '001', status: 'claimed', history: [] }));

    assert.throws(() => claimTask(taskFile, 'agent-1'), /not pending/);
  });
});

describe('updateTask', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('updates status and appends to history', () => {
    const taskFile = path.join(tmpDir, '001.json');
    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        status: 'claimed',
        claimedBy: 'agent-1',
        history: [{ status: 'claimed', agent: 'agent-1', timestamp: '...' }],
      }),
    );

    const result = updateTask(taskFile, 'complete', 'agent-1');
    assert.equal(result.status, 'complete');
    assert.equal(result.history.length, 2);
    assert.equal(result.history[1].status, 'complete');
  });
});

const { execFileSync } = require('node:child_process');

describe('CLI interface', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-test-'));
    // Write a config with task types (TOML format)
    fs.writeFileSync(
      path.join(tmpDir, 'config.toml'),
      [
        '[task-types.implement]',
        'priority = 50',
        'claude-md = "implementer.md"',
        '',
        '[task-types.review]',
        'priority = 90',
        'claude-md = "reviewer.md"',
      ].join('\n'),
    );
    fs.mkdirSync(path.join(tmpDir, 'tasks'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('claim returns task JSON when a task is available', () => {
    fs.writeFileSync(
      path.join(tmpDir, 'tasks', '001.json'),
      JSON.stringify({
        id: '001',
        type: 'implement',
        status: 'pending',
        blockedBy: [],
        claimedBy: null,
        history: [],
      }),
    );

    const result = execFileSync(
      'node',
      [
        path.join(__dirname, '..', 'lib', 'tasks.js'),
        'claim',
        path.join(tmpDir, 'tasks'),
        path.join(tmpDir, 'config.toml'),
        'agent-1',
        'implement',
      ],
      { encoding: 'utf8' },
    );

    const parsed = JSON.parse(result.trim());
    assert.equal(parsed.taskId, '001');
    assert.equal(parsed.taskType, 'implement');
  });

  it('claim exits with empty output when no tasks match', () => {
    const result = execFileSync(
      'node',
      [
        path.join(__dirname, '..', 'lib', 'tasks.js'),
        'claim',
        path.join(tmpDir, 'tasks'),
        path.join(tmpDir, 'config.toml'),
        'agent-1',
        'planning',
      ],
      { encoding: 'utf8' },
    );

    assert.equal(result.trim(), '');
  });

  it('update changes task status on disk', () => {
    const taskFile = path.join(tmpDir, 'tasks', '001.json');
    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        status: 'claimed',
        claimedBy: 'agent-1',
        history: [],
      }),
    );

    execFileSync(
      'node',
      [path.join(__dirname, '..', 'lib', 'tasks.js'), 'update', taskFile, 'complete', 'agent-1'],
      { encoding: 'utf8' },
    );

    const onDisk = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
    assert.equal(onDisk.status, 'complete');
  });
});
