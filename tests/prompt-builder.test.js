const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const { buildPrompt } = require('../lib/prompt-builder.js');

describe('buildPrompt', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'coordinator-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it('includes task description and acceptance criteria', () => {
    const taskFile = path.join(tmpDir, '001.json');
    const claudeMdFile = path.join(tmpDir, 'implementer.md');

    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        type: 'implement',
        description: 'Add user login',
        acceptanceCriteria: ['Validates email', 'Hashes password'],
        owns: ['src/auth.js'],
        touches: ['src/routes.js'],
      }),
    );
    fs.writeFileSync(claudeMdFile, '# Implementer\n\nYou are an implementer.');

    const prompt = buildPrompt(taskFile, claudeMdFile);
    assert.ok(prompt.includes('Add user login'));
    assert.ok(prompt.includes('Validates email'));
    assert.ok(prompt.includes('Hashes password'));
    assert.ok(prompt.includes('src/auth.js'));
    assert.ok(prompt.includes('You are an implementer'));
  });

  it('includes review feedback when present', () => {
    const taskFile = path.join(tmpDir, '001.json');
    const claudeMdFile = path.join(tmpDir, 'fixes.md');

    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        type: 'fixes',
        description: 'Fix login bug',
        acceptanceCriteria: [],
        owns: [],
        touches: [],
        reviewFeedback: [
          {
            reviewer: 'reviewer-1',
            verdict: 'changes-requested',
            comments: 'Missing null check on email field',
          },
        ],
      }),
    );
    fs.writeFileSync(claudeMdFile, '# Fixes');

    const prompt = buildPrompt(taskFile, claudeMdFile);
    assert.ok(prompt.includes('Missing null check on email field'));
    assert.ok(prompt.includes('changes-requested'));
  });

  it('works with no review feedback', () => {
    const taskFile = path.join(tmpDir, '001.json');
    const claudeMdFile = path.join(tmpDir, 'implementer.md');

    fs.writeFileSync(
      taskFile,
      JSON.stringify({
        id: '001',
        description: 'Simple task',
        acceptanceCriteria: [],
        owns: [],
        touches: [],
      }),
    );
    fs.writeFileSync(claudeMdFile, '# Implementer');

    const prompt = buildPrompt(taskFile, claudeMdFile);
    assert.ok(prompt.includes('Simple task'));
    assert.ok(!prompt.includes('Review Feedback'));
  });
});
