/**
 * Parse Spec-Kit tasks.md markdown format into JSON.
 * @param {string} markdown - The markdown content to parse
 * @returns {Array<Object>} Array of task objects
 */
function parseTasksMarkdown(markdown) {
  if (!markdown || markdown.trim() === '') {
    return [];
  }

  const lines = markdown.split('\n');
  const tasks = [];

  // Regex to match uncompleted tasks: - [ ] T001 [P] [US1] Description
  const taskRegex = /^- \[ \] (T\d+)\s+(.*)/;
  const parallelRegex = /\[P\]/;
  const userStoryRegex = /\[US(\d+)\]/;
  const fileRegex = /\b[\w\-./]+\/[\w\-./]+\.\w+\b/g;

  for (const line of lines) {
    const match = line.match(taskRegex);
    if (!match) continue;

    const taskId = match[1];
    let description = match[2].trim();

    // Extract markers
    const isParallel = parallelRegex.test(description);
    const userStoryMatch = description.match(userStoryRegex);
    const userStory = userStoryMatch ? `US${userStoryMatch[1]}` : null;

    // Remove markers from description
    description = description.replace(parallelRegex, '').replace(userStoryRegex, '').trim();

    // Extract file paths
    const files = description.match(fileRegex) || [];

    tasks.push({
      taskId,
      description,
      parallel: isParallel,
      userStory,
      files,
    });
  }

  return tasks;
}

module.exports = { parseTasksMarkdown };
