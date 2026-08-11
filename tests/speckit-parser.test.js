const { describe, it } = require('node:test');
const assert = require('node:assert');
const { parseTasksMarkdown } = require('../lib/speckit-parser.js');

describe('parseTasksMarkdown', () => {
  it('parses basic task', () => {
    const markdown = '- [ ] T001 Create project structure';
    const result = parseTasksMarkdown(markdown);
    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T001');
    assert.equal(result[0].description, 'Create project structure');
    assert.equal(result[0].parallel, false);
    assert.equal(result[0].userStory, null);
    assert.deepEqual(result[0].files, []);
  });

  it('parses parallel marker [P]', () => {
    const markdown = '- [ ] T002 [P] Implement feature';
    const result = parseTasksMarkdown(markdown);
    assert.equal(result[0].parallel, true);
    assert.equal(result[0].description, 'Implement feature');
  });

  it('parses user story label [US1]', () => {
    const markdown = '- [ ] T003 [US1] Add user model';
    const result = parseTasksMarkdown(markdown);
    assert.equal(result[0].userStory, 'US1');
    assert.equal(result[0].description, 'Add user model');
  });

  it('parses both [P] and [US2] markers', () => {
    const markdown = '- [ ] T004 [P] [US2] Create API endpoint';
    const result = parseTasksMarkdown(markdown);
    assert.equal(result[0].parallel, true);
    assert.equal(result[0].userStory, 'US2');
    assert.equal(result[0].description, 'Create API endpoint');
  });

  it('ignores completed tasks', () => {
    const markdown = `- [x] T001 Completed task
- [ ] T002 Active task`;
    const result = parseTasksMarkdown(markdown);
    assert.equal(result.length, 1);
    assert.equal(result[0].taskId, 'T002');
  });

  it('parses multiple tasks', () => {
    const markdown = `- [ ] T001 First task
- [ ] T002 [P] Second task
- [ ] T003 [US1] Third task`;
    const result = parseTasksMarkdown(markdown);
    assert.equal(result.length, 3);
    assert.equal(result[0].taskId, 'T001');
    assert.equal(result[1].taskId, 'T002');
    assert.equal(result[2].taskId, 'T003');
  });

  it('extracts single file path from description', () => {
    const markdown = '- [ ] T001 Implement auth in src/middleware/auth.py';
    const result = parseTasksMarkdown(markdown);
    assert.deepEqual(result[0].files, ['src/middleware/auth.py']);
    assert.equal(result[0].description, 'Implement auth in src/middleware/auth.py');
  });

  it('extracts multiple file paths from description', () => {
    const markdown = '- [ ] T001 Create User in src/models/user.py and tests/test_user.py';
    const result = parseTasksMarkdown(markdown);
    assert.deepEqual(result[0].files, ['src/models/user.py', 'tests/test_user.py']);
  });

  it('handles tasks with no markers', () => {
    const markdown = '- [ ] T005 Simple task description';
    const result = parseTasksMarkdown(markdown);
    assert.equal(result[0].parallel, false);
    assert.equal(result[0].userStory, null);
    assert.deepEqual(result[0].files, []);
  });

  it('returns empty array for empty input', () => {
    const result = parseTasksMarkdown('');
    assert.deepEqual(result, []);
  });

  it('handles file paths with hyphens and underscores', () => {
    const markdown = '- [ ] T001 Update lib/util-func.js and src/auth_service.py';
    const result = parseTasksMarkdown(markdown);
    assert.deepEqual(result[0].files, ['lib/util-func.js', 'src/auth_service.py']);
  });

  it('extracts root-level files', () => {
    const markdown = '- [ ] T001 Update README.md and package.json';
    const result = parseTasksMarkdown(markdown);
    assert.deepEqual(result[0].files, ['README.md', 'package.json']);
  });

  it('returns empty array for undefined input', () => {
    const result = parseTasksMarkdown(undefined);
    assert.deepEqual(result, []);
  });

  it('handles duplicate task IDs without throwing', () => {
    const markdown = `- [ ] T001 First task
- [ ] T001 Duplicate task ID`;
    const result = parseTasksMarkdown(markdown);
    assert.equal(result.length, 2);
    assert.equal(result[0].taskId, 'T001');
    assert.equal(result[1].taskId, 'T001');
    // Parser doesn't validate uniqueness - caller's responsibility
  });
});
