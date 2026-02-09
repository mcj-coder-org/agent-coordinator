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
