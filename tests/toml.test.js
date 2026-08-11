const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { parseTOML } = require('../lib/toml.js');

describe('parseTOML', () => {
  it('parses nested tables with string and number values', () => {
    const input = `
[task-types.fixes]
priority = 100
claude-md = "fixes.md"

[task-types.review]
priority = 90
claude-md = "reviewer.md"
`;
    const result = parseTOML(input);
    assert.deepEqual(result, {
      'task-types': {
        fixes: { priority: 100, 'claude-md': 'fixes.md' },
        review: { priority: 90, 'claude-md': 'reviewer.md' },
      },
    });
  });

  it('parses top-level key-value pairs', () => {
    const input = 'name = "test"\nversion = 1\n';
    const result = parseTOML(input);
    assert.deepEqual(result, { name: 'test', version: 1 });
  });

  it('ignores comments and blank lines', () => {
    const input = '# comment\nname = "test"\n\n# another\n';
    const result = parseTOML(input);
    assert.deepEqual(result, { name: 'test' });
  });

  it('parses arrays of strings', () => {
    const input = 'capabilities = ["impl", "review", "fixes"]\n';
    const result = parseTOML(input);
    assert.deepEqual(result, { capabilities: ['impl', 'review', 'fixes'] });
  });
});
