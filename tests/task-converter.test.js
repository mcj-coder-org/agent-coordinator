const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { convertToCoordinatorTask, buildDependencyGraph } = require('../lib/task-converter.js');

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
    assert.deepEqual(result.acceptanceCriteria, []);
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

describe('buildDependencyGraph', () => {
  it('returns empty blockedBy for task with no file conflicts', () => {
    const tasks = [
      {
        id: '001',
        owns: ['src/model.py'],
        touches: [],
        blockedBy: [],
      },
      {
        id: '002',
        owns: ['src/view.py'],
        touches: [],
        blockedBy: [],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, []);
  });

  it('blocks task that touches file owned by earlier task', () => {
    const tasks = [
      {
        id: '001',
        owns: ['src/model.py'],
        touches: [],
        blockedBy: [],
      },
      {
        id: '002',
        owns: [],
        touches: ['src/model.py'],
        blockedBy: [],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, ['001']);
  });

  it('blocks task that owns file touched by earlier task', () => {
    const tasks = [
      {
        id: '001',
        owns: [],
        touches: ['src/model.py'],
        blockedBy: [],
      },
      {
        id: '002',
        owns: ['src/model.py'],
        touches: [],
        blockedBy: [],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, ['001']);
  });

  it('blocks task with multiple dependencies', () => {
    const tasks = [
      {
        id: '001',
        owns: ['src/model.py'],
        touches: [],
        blockedBy: [],
      },
      {
        id: '002',
        owns: ['src/view.py'],
        touches: [],
        blockedBy: [],
      },
      {
        id: '003',
        owns: [],
        touches: ['src/model.py', 'src/view.py'],
        blockedBy: [],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, []);
    assert.deepEqual(result[2].blockedBy, ['001', '002']);
  });

  it('handles complex dependency chains', () => {
    const tasks = [
      {
        id: '001',
        owns: ['src/model.py'],
        touches: [],
        blockedBy: [],
      },
      {
        id: '002',
        owns: [],
        touches: ['src/model.py'],
        blockedBy: [],
      },
      {
        id: '003',
        owns: [],
        touches: ['src/model.py'],
        blockedBy: [],
      },
    ];

    const result = buildDependencyGraph(tasks);

    assert.deepEqual(result[0].blockedBy, []);
    assert.deepEqual(result[1].blockedBy, ['001']);
    assert.deepEqual(result[2].blockedBy, ['001', '002']);
  });
});
