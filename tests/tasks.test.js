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

  it('returns empty when no tasks match', () => {
    const result = findClaimable(tasks, ['planning'], taskTypes, tasks);
    assert.equal(result.length, 0);
  });
});
