const fs = require('node:fs');

function buildPrompt(taskFile, claudeMdFile) {
  const task = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
  const claudeMd = fs.readFileSync(claudeMdFile, 'utf8');

  const sections = [];

  sections.push(claudeMd);
  sections.push(`\n## Task: ${task.id}\n`);
  sections.push(`**Description:** ${task.description}\n`);

  if (task.acceptanceCriteria?.length) {
    sections.push('**Acceptance Criteria:**');
    task.acceptanceCriteria.forEach((c) => sections.push(`- ${c}`));
    sections.push('');
  }

  if (task.owns?.length) {
    sections.push(`**Files you own (exclusive):** ${task.owns.join(', ')}`);
  }
  if (task.touches?.length) {
    sections.push(`**Files you may touch (shared):** ${task.touches.join(', ')}`);
  }

  if (task.reviewFeedback?.length) {
    sections.push('\n## Review Feedback\n');
    task.reviewFeedback.forEach((fb) => {
      sections.push(`**${fb.reviewer}** — ${fb.verdict}`);
      sections.push(fb.comments);
      sections.push('');
    });
  }

  return sections.join('\n');
}

module.exports = { buildPrompt };

if (require.main === module) {
  const [, , taskFile, claudeMdFile] = process.argv;
  if (!taskFile || !claudeMdFile) {
    console.error('Usage: node prompt-builder.js <task.json> <claude-md-file>');
    process.exit(1);
  }
  console.log(buildPrompt(taskFile, claudeMdFile));
}
